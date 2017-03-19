TABLE OF CONTENTS:
====================

!! TODO: implement nvims job_control.txt

1. list of plugins using vim-addon-async (SCREENSHOTS!)
2. GOAL (provide API for Vim users)
3. porcelain LogToBuffer running interactive interpreter shells within Vim buffers
4. installation & implementation details
4.1. customization
5. usage tips
6. credits
7. related work
8. yet another example
8. tips
10. TROUBLE?
11. testing new implementations
12. TODO


# 1) List of Plugins Using vim-addon-async:

- ensime (Scala server providing fast type checking and completion)
- vim-addon-xdebug (xdebug implementation for Vim)
- vim-addon-rdebug (simple ruby debugging using require "debug")

#### REPL (read print eval loop) implementations are available for

- **Scala**
- **Ruby** [1] 
  ![ruby-completion](https://raw.github.com/MarcWeber/vim-addon-async/master/screen-shots/vim-addon-async-ruby-repl.png)
- **PHP**
    works: $arr_var    : list keys, [ is prefixed
           obj      : list methods,properties -> is prefixed

- **Python** [1] 
  ![python-completion](https://raw.github.com/MarcWeber/vim-addon-async/master/screen-shots/vim-addon-async-python-repl.png)


    works: dict["    : list keys
           obj.      : list dir() output
           (nothing) : list globals

could be done:

- **PHP** - There is lot's of introspection eg see http://docstore.mik.ua/orelly/webprog/php/ch06_05.htm, php -a runs the interpreter



providing completion on objects etc.

[1]: the interpreter is used. eg dir(obj) for python and .methods for Ruby.
This means you have to take care that you don't cause side effects when
invoking the completion!

Example showing how to run a background process in the async buffer while
continuing typing in another buffer:
http://mawercer.de/~marc/vim-addon-async-sh-example.jpg

# 2) Goal: Provide API for Vim Users

provide an async communication interface for VimL which can be implemented in different ways.

It looks like this:

```VimL
  let ctx = { 'cmd' : '/bin/sh' }
  fun ctx.receive(data, ...)
    " ... will contain the file descriptor number or such in the future
    echo "got data: ".a:data
    " now that we have the date the process is no longer needed:
    self.kill()
  endf
  call async#Start(ctx)
  call ctx.write("date") " run date
```

What's nice about this design? You can add your own state to the context easily.
Eg the LogToBuffer keeps state in a "pending" key which makes the code aware about
whether the last block of bytes contained a "\n" character at the end or not.

For debugger implementations etc this means you can keep lists of breakpoints
etc easily.

Different implementations will be provided. See below.

# 3) porcelain LogToBuffer running interactive interpreter shells within Vim buffers:

How powerful this simple interface is is illustrated by
LogToBuffer which is porcelain on top of the API:

```VimL
call async_porcelaine#LogToBuffer({'cmd':'python -i', 'move_last':1, 'prompt': '^>>> $'})
```

should yield:

```
pid: 27475, bufnr: 4
> Python 2.6.5 (r265:79063, May  9 2010, 14:26:02) 
> [GCC 4.4.3] on linux2
> Type "help", "copyright", "credits" or "license" for more information.
```

Note the "\_" Everything below that will be sent to the interpreter's stdin when pressing <space><cr>
You can also visually select arbitrary text and press <cr> to send those lines instead.

Eg try this:

```python
# this comment starts at "no" indentation. keep the empty line for python interpreter!
def foo(text):
  print text

foo("hello world")
```

Pay attention: the ```async#GetLines``` script will sent #1 and #2 when
pressing ```<space><cr>``` in the num2 line. I recommend using ```<c-u><cr>```
in order to enter a blank line if you want to prevent this
and you should get the reply:

```
> >>> ... ... ... >>> hello world
```

the ```>>> ... .... ... >>>``` could be filtered by the "prompt" setting.

**Note:** because adding lines to background buffers are be annoying actions can be
delayed. In the LogToBuffer updates are delayed when

- you're in insert / visual mode (Vim should not disturb you when typing, selecting)
- you're in command line or command win buffer (q:)
  Reason: You can't switch buffers or tabs when its open.

# 4) Installation & Implementation Details:

This plugin depends on vim-addon-signs. Thus I recommend using
vim-addon-manager for installing this addon.

For now I recommend using impl 2) (gvim) or impl 1) (non gui version of Vim)

## Implementation 1 (native)

(out of order because API changed - current upstream of this patch is here
 http://github.com/bartman/vim )

compile my async version of Vim (github.com/MarcWeber/vim branch "work").
(-) doesn't work in gui very well yet. That's why its not used in that case
(-) patch as to be tested with valgrind and tidied up

## Implementation 2 (C Executable)

compile C/vim-addon-async-helper.c:

```sh
cd C; gcc -o vim-addon-async-helper vim-addon-async-helper.c
```

(-) requires client server (X connection or the like
(-) 20ms delay (vim -> app)

tested on linux and OSX. It should be easy to find a way to make the helper
app run on Windows as well.. Any volunteers ?

## Implementation 3 (possible others)
- mzscheme (racket)
  implementation using threads. That would be the only solution working everywhere.
  (+) portable)
  (-) not implemented yet
  (_) very view users have mzscheme support
 
- python (also calling back into Vim cause its not threadsafe, but passing
  data to Python could be done easily)
  (ZyX says threads may not work on arm, but processes might)

# 4b) Customization

you can change / remove the default prefix which is added to lines output by
processes when using ```LogToBuffer```:

~/.vimrc:
```VimL
let g:async = {'line_prefix' = "other : " }
```

The line_prefix was chosen so that its easier to distinguish "input" from
"output".

The stdin input has no prefix so that editing behaves the way you know.

# 5) Usage Tips:

create your own custom commands like this

```VimL
" AsyncSh only works in gvim. if you use vim it magically suspends? Probably
" some signals taking a wrong path (?)
command! AsyncSh  call async_porcelaine#LogToBuffer({'cmd':'/bin/sh -i', 'move_last':1, 'prompt': '^.*\$[$] '})

command! AsyncCoq call async_porcelaine#LogToBuffer({'cmd':'coqtop', 'move_last':1, 'prompt': '^Coq < '})
command! AsyncRubyIrb call repl_ruby#RubyBuffer({'cmd':'irb','move_last' : 1})
command! AsyncPHP call repl_php#PHPBuffer({'cmd':'php -a','move_last' : 1})
command! AsyncSML call repl_ruby#RubyBuffer({'cmd':'sml','move_last' : 1, 'prompt': '^- '})
command! AsyncPython call repl_python#PythonBuffer({'cmd':'python -i','move_last' : 1, 'prompt': '^>>> '})
command! AsyncScala call async_porcelaine#ScalaBuffer({'cmd':'scala','move_last' : 1, 'prompt': '^scala> '})
command! AsyncLogicblox call repl_logicblox#LogicbloxBuffer({'move_last' : 1})

```

A history has been implemented. Press ```<c-h>``` to use select a line you've used
previously. Or press ```<c-x><c-h>``` to get completion in buffer.
See ```plugin/vim-addon-async.vim``` for file location and max lines

# 6) Credits:

Thanks to:

  * **Bart Trojanowski** who provided the initial C implementation of the Vim patch
    (Thus he did most of the work)

  * **Sergey Khorev** who provided the initial racket (scheme implementation) code
    Someone (me?) still has to make it complete.


# 7) Related Work:

Nico Raffo told me that he's been working on a idle timer like event for Vim.
This would be another perfect match to provide a different implementation.

http://www.vim.org/scripts/script.php?script_id=4336

[vimproc plugin](http://github.com/Shougo/vimproc/tree/master/doc/)
- TODO: put more details here

[Conque Shell plugin](http://code.google.com/p/conque)

- looks like being a complete terminal emulator trying to map terminal
  commands to Vim buffer?
  Thus Conque can do much more than vim-addon-async. It can even run vim
  inside gvim!
- must be in insert mode to receive screen updates
- probably more cross platform
- probably causing less crashes
- TODO: put more details here, read its documentation
- Neovim

[Screen (vim + gnu screen/tmux)](http://www.vim.org/scripts/script.php?script_id=2711)

Simulate a split shell, using gnu screen or tmux

This was announced on the mailinglist (client-server without X):
http://code.google.com/r/yukihironakadaira-vim-cmdsrv-nox/
clone then hg update -C cmdsrv-nox works perfectly without X!

[Vim Remote Library](https://github.com/ynkdir/vim-remote)

http://vim.wikia.com/wiki/Execute_external_programs_asynchronously_under_Windows

Implementation based on netbeans protocol:
[vim-async-beans]https://github.com/jlc/vim-async-beans

(using python thread and CursorHold event):
[shellasync.vim](https://github.com/troydm/shellasync.vim)

[conque repl](http://www.vim.org/scripts/script.php?script_id=4222)

[vim-dispatch](https://github.com/tpope/vim-dispatch)

# 8) Yet Two Other Examples:

```VimL
fun! s:Add(s)
  let l = [{'text': string(a:s)}]
  call setqflist(l, 'a')
endf

" ctx 1
let ctx = { 'cmd' : 'nr=1; while read f; do nr=`expr $nr + 1`; sleep 1; echo $nr $f - pong; if [ $nr == 5 ]; then break; fi; done; exit 12' }
fun ctx.receive(data, ...)
  call s:Add(string(a:text))
  call async_write(self, "ping\n")
endf

fun ctx.started()
  call s:Add("ctx1: process started. pid:  ". self.pid)
endf

fun ctx.terminated()
  call s:Add("ctx1: process died. status (should be 12): ". self.status)
endf

call async_exec(ctx)
call async_write(ctx, "ping\n")


" ctx2 2
let ctx2 = { 'cmd' : 'find / | while read f; do echo $f; sleep 1; done' }

fun ctx2.receive(type, text)
  call s:Add('ctx22: '.string(a:text))
endf

fun ctx2.started()
  call s:Add("ctx22: process started. pid:  ". self.pid)
endf

fun ctx2.terminated()
  call s:Add("ctx22: process died. status:  ". self.status)
endf
call async_exec(ctx2)
```

# 9) Tips

this debugging worked best for me:
```VimL
call append('$', string)
```

# 10) Troubleshooting

### MAC/OSX/Linux/...:
If vim in PATH does not support client-server nothing will happen. You have to
tell VAM which path to pass to the externel helper by putting this into your .vimrc:

```VimL
  let g:async = {'vim' : 'path-to-vim-executable-supporting-client-server'}
```

On OSX it is likely to be macvim. You can achieve the same by symlinking
macvim or vimx or whatsoever to vim.

Currently only "Implementation 2" is fully supported (see above). This means

1.  ```:echo has('clienserver')``` must report 1
2.  ```:echo v:clientserver``` must not be null ( pass vim --servername NAME )
3.  You must have the c executable compiled (The plugin should try doing this for
    you though). Search for gcc above to learn how to compile it manually

I recommend using a command like this for debugging:

```VimL
call async_porcelaine#LogToBuffer({'cmd':'/bin/sh -i', 'debug_process' : 1 }) 
```

**More notes:**

Using the client-server I faced several issues:

- if there is a VimL error you don't see it (try using debug or run the code
  manually within Vim)

- some commands seem to behave strange.
  Eg in vim-addon-xdebug I had to switch off syntax else Vim crashes.
  Also "normal jdd" seem to never return in one case

Summary: Everything seems to work fine if you're willing to spend some time on
finding workarounds on some commands. If you have issues contact me and I'll
try to help.


# 11) Testing New Implementations

try running this test which checks whether all characters (0 - 255) are quoted
correctly:

```VimL
call vim_addon_async_tests#Binary()
call vim_addon_async_tests#Chunksize()
```


# 12) Todo

- find out about the prompt automatically by pressing enter multiple times.
  (eg irb also prints the line number. So maybe it should not be skipped?)

- Would such a function make sense: ? Maybe even having a timeout?

  async_read_until({ctx}, {string} -- read bytes from stdout until one of the
                                    chars contained in string is found
                                 -- this way you can read lines etc easily.
                                    Don't know yet how useful it is. This way
                                    you can implement "blocking" read features
                                    if you have to.
                                    Example use case would be completion.
                                    Another way would be returning no
                                    completions restarting completion task if
                                    cursor didn't move and the completion
                                    results are received by the specified
                                    receive function



