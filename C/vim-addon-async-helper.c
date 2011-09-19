#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>


 // wait 50ms before polling again
#define TOWAIT 20
// #define BUF_SIZE 4048
#define BUF_SIZE 259072

#define SHELL_NAME "sh"
#define SHELL "/bin/sh"

/* author: Marc Weber
 * license: same as Vim .c code
 *
 * purpose: helper app providing one async implementation for vim-addon-async.
 * from-vim-file: Vim will write to this file. The loop will pick it up and feed
 * it into stdin of the process.
 *
 * If stdout/err text is received the data is send to viem using --remote-expr
 *
 * I'm not a C programmer. So this code may contain bugs. Bear with me and help
 * me improve it. But hey, it works!
 *
 * Qute some code was copied from vim source code
 *
 * I should never have started this helper app in C.
 * TODO: rewrite using a sane scripting language (perl, ruby, pyhton, ..)
 */ 

void usage(char * name){
  printf("%s vim-executable vim-server-name process_id from-vim-file to-vim-file cmd_max_chars cmd\n", name);
}

void my_die(char * msg){
  printf("%s\n", msg);
  exit(1);
}

static void
simulate_dumb_terminal()
{

    int Columns = 80;
    int Rows = 24;

# ifdef HAVE_SETENV
    char	envbuf[50];
    setenv("TERM", "dumb", 1);
    sprintf((char *)envbuf, "%ld", Rows);
    setenv("ROWS", (char *)envbuf, 1);
    sprintf((char *)envbuf, "%ld", Rows);
    setenv("LINES", (char *)envbuf, 1);
    sprintf((char *)envbuf, "%ld", Columns);
    setenv("COLUMNS", (char *)envbuf, 1);
# else
    static char	envbuf_Rows[20];
    static char	envbuf_Columns[20];
    /*
     * Putenv does not copy the string, it has to remain valid.
     * Use a static array to avoid losing allocated memory.
     */
    putenv("TERM=dumb");
    sprintf(envbuf_Rows, "ROWS=%ld", Rows);
    putenv(envbuf_Rows);
    sprintf(envbuf_Rows, "LINES=%ld", Rows);
    putenv(envbuf_Rows);
    sprintf(envbuf_Columns, "COLUMNS=%ld", Columns);
    putenv(envbuf_Columns);
# endif
}

// target size should be
// strlen(type) + 3 + strlen(from) * 3 + 5
// Because Vim can't cope with '\0' bytes vimQuote
// encodes a Vim list. If a \0' byte is found a new list item is started
void vimQuote(char * ptr, int size, char * target){

  char * target_start;

  *target++ = '[';
  *target++ = '"';
  // encode remaining data as additional list items
  while (size-- > 0){
    switch (*ptr){
      case '\\' :  
        *target++ = '\\';
        *target++ = '\\';
        break;
      case '\n' :  
        *target++ = '\\';
        *target++ = 'n';
        break;
      case '\r' :  
        *target++ = '\\';
        *target++ = 'r';
        break;
      case '"' :  
        *target++ = '\\';
        *target++ = '"';
        break;
      case '\0' :  
        // quote \0 by starting a new list item
        *target++ = '"';
        *target++ = ',';
        *target++ = '"';
        break;
      default :
        *target++ = *ptr;
    }

    // Vim can't handle 0 bytes. So replace them by \n
    if (*target == 0)
      *target = '\n';

    ptr++;
  }
  *target++ = '"';
  *target++ = ']';
  *target++ = '\0';
}

static int cmd_max_chars = 0; // set in main

void send(char * vimExecutable, char *vimServerName, char * processId, char * type, char * buf, int read_bytes, char * toVim){
  char command[50 + BUF_SIZE+3];
  if (strlen(type) > 4){
    my_die("type must not be longer than 4 chars\n");
  }

  char quoted[7+3*BUF_SIZE+5];

  vimQuote(buf, read_bytes, quoted);
  int len = strlen(quoted);
  int use_file = len > cmd_max_chars;
  if (use_file){
    FILE * f = fopen(toVim, "w");
    if (!f) my_die("could'nt create output file for sending data to Vim!");
    int written = fwrite(&quoted[0], 1, len, f);
    if (written != len){
      printf("%d %d\n", written, len);
      my_die("couldn't write all bytes to file");
    }
    fclose(f);
    snprintf(command, sizeof(command), "async#Receive(\"%s\",\"%s\")", processId, type);
  } else {
    snprintf(command, sizeof(command), "async#Receive(\"%s\",\"%s\",%s)", processId, type, quoted);
  }
   

  char * argv3[6];
  argv3[0] = vimExecutable;
  argv3[1] = "--servername";
  argv3[2] = vimServerName;
  argv3[3] = "--remote-expr";
  argv3[4] = command;
  argv3[5] = NULL;

  int i;
  for (i = 0; i < 5; i++) {
    printf("arg %d %s\n", i, argv3[i]);
  }

  int pid2;

  pid2 = fork();
  if (pid2 == -1) {
    printf("fork failed\n");
  } else if (pid2 == 0) { /* child */
    execvp(vimExecutable, argv3);
    exit(-1);
  }
  // parent waits for sending data:
  int status;
  while (1){
    waitpid(pid2, &status, 0);
    if (WIFEXITED(status) && WEXITSTATUS(status) != 0)
      printf("sending failed!\n");
    if (WIFEXITED(status))
      break;
  }

  if (use_file){
    printf("waiting for vim reading data file\n");
    // wait until Vim has deleted the file
     struct timeval  tv;
     tv.tv_sec = TOWAIT / 1000;
     tv.tv_usec = (TOWAIT % 1000) * (1000000/1000);

     while (1){
       int ret = select(0, NULL, NULL, NULL, &tv);
       FILE * f = fopen(toVim, "r");
       if (!f) break;
       fclose(f);
     }
    printf("finished waiting\n");
  }
}

void unquote(char * ptr, int buf_count, char * target, int * written){
   *written = 0;

   while (buf_count-- > 0){
      switch (*ptr){
        case '\\' :  
          ptr++;
          buf_count--;
          *target = *ptr++;
          if (*target == '0') *target = '\0';
          *target++;
          break;
        default :
          *target++ = *ptr++;
      }
      (*written)++;
   }
}


int vim_alive(char * vimExecutable, char * vimServerName){

  char * argv3[6];
  int pid3;
  int pipe_error;
  int fd_fromvim[2];
  int ignored;

  argv3[0] = vimExecutable;
  argv3[1] = "--servername";
  argv3[2] = vimServerName;
  argv3[3] = "--remote-expr";
  argv3[4] = "v:servername";
  argv3[5] = NULL;

  pipe_error = (pipe(fd_fromvim) < 0);
  if (pipe_error){
    printf("creating pipe failed\n");
    return 0; // force exit
  }

  pid3 = fork();
  if (pid3 == -1) {
    printf("fork failed\n");
    return 0;
  } else if (pid3 == 0) { /* child */

    close(fd_fromvim[0]);
    close(1);
    ignored = dup(fd_fromvim[1]);

    execvp(vimExecutable, argv3);
    exit(-1);
  }
  /* parent */
  close(fd_fromvim[1]);
#define BUFSIZE2 1024
  char buf[BUFSIZE2];

  int read_bytes2 = read(fd_fromvim[0], &buf[0], (BUFSIZE2-1));
  buf[read_bytes2] = 0;

  close(fd_fromvim[0]);

  // kill vim if its still running ..
  kill(pid3, SIGKILL);

  // expect that vim printed the servername on stdout
  return NULL != strstr(&buf[0], vimServerName);

}

int main(int argc, char * argv[])
{

  int i;
  if (argc < 8) {
    usage(argv[0]);
  } else {
    argv++; argc--;
    char * vimExecutable = argv[0];
    char * vimServerName = argv[1];
    char * processId     = argv[2];
    char * inputFile     = argv[3]; // from Vim to this tool
    char * toVim         = argv[4]; // if more than cmd_max_chars were received use a file to pass data to Vim for performance reasons
    cmd_max_chars    = atoi(argv[5]);
    char * cmd           = argv[6];
    int    pipe_error = 0;


    // this is mostly copied from vim code (mch_start_async_shell)
    int	fd_fromshell[2];
    int	fd_toshell[2];
    int fd_from;
    int fd_to;
    int pid_child = 0; // pid target process
    int pidInut = 0; // process reading input from vim feeding it to target process
    int ignored;


    // create communication pipes:
    pipe_error = (pipe(fd_fromshell) < 0);
    if (pipe_error) {
	printf("creating pipe failed\n");
	goto error_pipe_from;
    }
    pipe_error = (pipe(fd_toshell) < 0);
    if (pipe_error) {
	printf("creating pipe failed\n");
	goto error_pipe_to;
    }

    // fork and close pipe ends
    pid_child = fork();
    if (pid_child == -1) {
	printf("fork failed\n");
	goto error_fork;

    } else if (pid_child == 0) { /* child */
	simulate_dumb_terminal();

	/* set up stdin for the child */
	close(fd_toshell[1]);
	close(0);
	ignored = dup(fd_toshell[0]);
	close(fd_toshell[0]);

	/* set up stdout/stderr for the child */
	close(fd_fromshell[0]);
	close(1);
	ignored = dup(fd_fromshell[1]);
	close(2);
	ignored = dup(fd_fromshell[1]);
	close(fd_fromshell[1]);

        char * argv[3];
        argv[0] = SHELL_NAME;
        argv[1] = "-c";
        argv[2] = cmd;
        argv[3] = 0;

        execv(SHELL, argv);
    }

    /* parent */
    close(fd_fromshell[1]);
    close(fd_toshell[0]);
    fd_from = fd_fromshell[0];
    fd_to   = fd_toshell[1];


    // set non blocking:

    // notify Vim about pid:
    char s_pid[10];
    snprintf(&s_pid[0], sizeof(s_pid), "%d", pid_child);
    send(vimExecutable, vimServerName, processId, "pid", s_pid, strlen(s_pid), toVim);

    // process watching for vim -> process input:

    // fork and close pipe ends
    pidInut = fork();
    if (pid_child == -1) {
	printf("fork failed\n");
	goto error_fork;

    } else if (pidInut == 0) { /* child */
       while (1){
         FILE * f_input = fopen(inputFile, "r");
         int read_bytes;
         char buf[BUF_SIZE];
         char to_sent[2*BUF_SIZE];

         // check for input .. probably I should be creating a fifo ..
         if (f_input != NULL) {
           printf("got file from vim \n");
           read_bytes = fread(&buf, 1, (BUF_SIZE-1), f_input);
           buf[read_bytes] = 0;
           printf("got bytes: %d \n%s\n", read_bytes, &buf[0]);

           char buf_to_sent[2*BUF_SIZE];
           int to_sent;
           unquote(buf, read_bytes, &buf_to_sent[0], &to_sent);
           size_t written = write(fd_to, &buf_to_sent[0], to_sent);
           if (written != to_sent) printf("failed writing all bytes\n");
           printf("%d bytes written to stdin of process\n", to_sent);
           fclose(f_input);
           unlink(inputFile);
         }

         struct timeval  tv;
         tv.tv_sec = TOWAIT / 1000;
         tv.tv_usec = (TOWAIT % 1000) * (1000000/1000);

         int ret = select(0, NULL, NULL, NULL, &tv);
       }
    }

    // poll / select loop

     int read_bytes;
     char buf[BUF_SIZE];

     int vim_alive_counter = 100;


     while (1){
       fd_set		rfds, efds;

       FD_ZERO(&rfds); /* calls bzero() on a sun */
       FD_ZERO(&efds);

       FD_SET(fd_from, &rfds);
       FD_SET(fd_from, &efds);

       struct timeval  tv;

       tv.tv_sec = TOWAIT / 1000;
       tv.tv_usec = (TOWAIT % 1000) * (1000000/1000);

       int ret = select(fd_from +1, &rfds, NULL, &efds, &tv);
       if (ret > 0){
         printf("got data\n");
         ret--;
         // read_bytes and send buf to Vim

         read_bytes = read(fd_from, &buf[0], BUF_SIZE-1);
         printf("sending bytes: %s, len %d\n", &buf[0], read_bytes);
         send(vimExecutable, vimServerName, processId, "data", buf, read_bytes, toVim);
         // wait until Vim has read the data
         if (read_bytes == 0)
           goto terminate;
       }  else {
         // char b_[21];
         // read(fd_from, b_, 20);
         // buf[20] = 0;
         // printf("read: %s\n", b_);
       }

       if (vim_alive_counter-- == 0){
         vim_alive_counter = 100;
         // check that vim is still alive
         //
         if (!vim_alive(vimExecutable, vimServerName)){
           printf(" ==================== vim has died? quitting\n");
           goto terminate;
         }
       }
     }

    int status;
    int rc;
terminate:

   kill(pidInut, SIGKILL);
   printf("%d child \n", pid_child);
   kill(pid_child, SIGKILL);

   printf("waiting for termination\n");
   if ( waitpid(pid_child, &status, WNOHANG) == 0 ) {
       // comments see vim code
       kill(pid_child, SIGKILL);
       rc = waitpid(pid_child, &status, 0);
   }

   char code[8];
   snprintf(&code[0], sizeof(code), "%d", status);
   send(vimExecutable, vimServerName, processId, "died", code, strlen(code), toVim);

error_fork:
   close(fd_toshell[0]);
   close(fd_toshell[1]);
error_pipe_to:
   close(fd_fromshell[0]);
   close(fd_fromshell[1]);
error_pipe_from:


   return;
  }

}
