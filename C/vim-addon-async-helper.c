#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>


 // wait 50ms before polling again
#define TOWAIT 20
#define BUF_SIZE 4048

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
 */ 

void usage(char * name){
  printf("%s vim-executable vim-server-name process_id from-vim-file cmd\n", name);
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

// target should be strlen(from) * 2 + 2
void vimQuote(char * ptr, char * target){

  *target++ = '\"';
  while (*ptr){
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
      default :
        *target++ = *ptr;
    }
    ptr++;
  }
  *target++ = '\"';
  *target++ = 0;
}

void send(char * vimExecutable, char *vimServerName, char * processId, char * buf, int read_bytes){
  char command[2*BUF_SIZE+1];
  char quoted[2*BUF_SIZE+3];

  vimQuote(buf, quoted);
  snprintf(command, sizeof(command), "async#Receive(\"%s\", %s)", processId, quoted);

  char * argv3[6];
  argv3[0] = vimExecutable;
  argv3[1] = "--servername";
  argv3[2] = vimServerName;
  argv3[3] = "--remote-expr";
  printf("command is %s\n", command);
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
}

int main(int argc, char * argv[])
{

  int i;
  if (argc < 6) {
    usage(argv[0]);
  } else {
    argv++; argc--;
    char * vimExecutable = argv[0];
    char * vimServerName = argv[1];
    char * processId     = argv[2];
    char * inputFile     = argv[3]; // from Vim to this tool
    char * cmd           = argv[4];
    int    pipe_error = 0;


    // this is mostly copied from vim code (mch_start_async_shell)
    int	fd_fromshell[2];
    int	fd_toshell[2];
    int fd_from;
    int fd_to;
    int pid;
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
    pid = fork();
    if (pid == -1) {
	printf("fork failed\n");
	goto error_fork;

    } else if (pid == 0) { /* child */
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

        if (0 != system(cmd)){
          printf("starting cmd %s failed\n", cmd);
          exit(1);
        } else {
          exit(0);
        }
    }

    /* parent */
    close(fd_fromshell[1]);
    close(fd_toshell[0]);
    fd_from = fd_fromshell[0];
    fd_to   = fd_toshell[1];


    // set non blocking:

    // notify Vim about pid:
    char s_pid[10];
    snprintf(&s_pid[0], sizeof(s_pid), "p%d", pid);
    send(vimExecutable, vimServerName, processId, s_pid, strlen(s_pid));

    // poll / select loop

     int read_bytes;
     char buf[BUF_SIZE];



     while (1){
       FILE * f_input = fopen(inputFile, "r");

       // check for input .. probably I should be creating a fifo ..
       if (f_input != NULL) {
         printf("got file from vim \n");
         read_bytes = fread(&buf, 1, BUF_SIZE-1, f_input);
         buf[read_bytes] = 0;
         printf("got bytes: %d \n%s\n", read_bytes, &buf[0]);
         size_t written = write(fd_to, &buf[0], read_bytes);
         if (written != read_bytes) printf("failed writing all bytes\n");
         fclose(f_input);
         unlink(inputFile);
       }

       fd_set		rfds, efds;

       FD_ZERO(&rfds); /* calls bzero() on a sun */
       FD_ZERO(&efds);

       FD_SET(fd_from, &rfds);
       FD_SET(fd_from, &efds);

       struct timeval  tv;
       struct timeval	*tvp;

       tv.tv_sec = TOWAIT / 1000;
       tv.tv_usec = (TOWAIT % 1000) * (1000000/1000);

       int ret = select(fd_from +1, &rfds, NULL, &efds, &tv);
       if (ret > 0){
         printf("got data\n");
         ret--;
         // read_bytes and send buf to Vim

         buf[0] = 'd';
         read_bytes = read(fd_from, &buf[1], BUF_SIZE-1);
         buf[read_bytes+1] = 0;
         printf("sending bytes: %s\n", &buf[1]);
         send(vimExecutable, vimServerName, processId, buf, read_bytes + 1);
         // wait until Vim has read the data
         if (read_bytes == 0)
           goto terminate;
       }  else {
         // char b_[21];
         // read(fd_from, b_, 20);
         // buf[20] = 0;
         // printf("read: %s\n", b_);
       }
     }

    int status;
    int rc;
terminate:

    if ( waitpid(pid, &status, WNOHANG) == 0 ) {
        // comments see vim code
        kill(pid, SIGTERM);
        rc = waitpid(pid, &status, 0);
    }

    char code[8];
    snprintf(&code[0], sizeof(code), "k%d", status);
    send(vimExecutable, vimServerName, processId, code, strlen(code));

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
