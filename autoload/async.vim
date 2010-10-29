" different impls are possible:
" - async patch for Vim
" - scheme impl (which supports kind of cooperative threads)
" - python  or external C executable calling back into Vim using client-server
"   feature

if !exists('g:async_implementation')
  let g:async_implementation = 'auto'
endif

let s:impl = {'supported': 'no'}

" tool {{{ 1

fun! async#AppendBuffer(bnr, lines, moveLast)
  if 0 && exists('*withcurrentbuffer')
    call withcurrentbuffer(a:bnr, function('append'), [a:lines])
   else
     " TODO avoid splitting if buffer was open - use lazyredraw etc
     sp
     exec 'b '.a:bnr
     call append('$', a:lines)
     if a:moveLast
       exec "normal G"
     endif
     q!
   endif
endf

let g:rec = []

" joins the lines meant to be sent to a process
" Eg this example assumes they all lines are prefixed by >
" example : async#GetLines('^>\zs.*\ze')
fun! async#GetLines(prefix)
  let idx = line('.')
  let lines = []
  while getline(idx) =~ a:prefix
    call add(lines, matchstr(getline(idx), a:prefix))
    let idx -= 1
  endw
  return join(reverse(lines),"\n")
endf

" run an interpreter (eg python, scala, ..), dropping the prompt.
" This function also handles incomplete lines.
" 
" All lines starting with '> ' will be passed to the interpreter.
" type o to start writing a line, type <space><cr> to sent it.
"
" examples:
"   call async#LogToBuffer({'cmd':'python -i', 'move_last':1, 'prompt': '^>>> $'})
"   call async#LogToBuffer({'cmd':'scala','move_last':1, 'prompt': 'scala> $'})
"   call async#LogToBuffer({'cmd':'/bin/sh', 'move_last':1, 'prompt': '^.*\$[$] '})
"
"   Example testing that appending to previous lines works correctly:
"   call async#LogToBuffer({'cmd':'sh -c "es(){ echo -n \$1; sleep 1; }; while read f; do echo \$f; es a; es b; es c; echo; done"', 'move_last':1})
fun! async#LogToBuffer(ctx)
  let ctx = a:ctx
  sp | enew
  let ctx.bufnr = bufnr('%')
  let b:ctx = ctx
  let prefix = '> '
  exec 'noremap <buffer> o o'.prefix
  exec 'noremap <buffer> O O'.prefix
  exec 'inoremap <buffer> <cr> <cr>'.prefix
  exec 'noremap <buffer> <space><cr> :call<space>async#Write(b:ctx, async#GetLines(''^'.prefix.'\zs.*\ze'')."\n")<cr>'
  exec 'inoremap <buffer> <space><cr> <esc>:call<space>async#Write(b:ctx, async#GetLines(''^'.prefix.'\zs.*\ze'')."\n")<cr>'
  fun! ctx.started()
    call async#AppendBuffer(self.bufnr, "pid: " .self.pid, 1)
  endf
  fun! ctx.receive(type, text)
    try
      " debug output like this
      " call append('0', 'rec: '.substitute(substitute(a:text,'\r', '\\r','g'), '\n', '\\n','g'))

      " in rare cases it happens that a line is sent in two parts: eg "p" and "rint\n"
      " write the "p" to the last line, but remember that there was no trailing
      " \n by assigning it to pending.

      let lines = split(a:text, '[\r\n]\+', 1)
      if has_key(self, 'pending')
        " drop pending line, it will be readded with rest of line
        normal Gdd
        let lines[0] = self.pending .lines[0]
      endif
      if lines[-1] == '' || (has_key(self, 'prompt') &&  lines[-1] =~ self.prompt)
        " trailing \n or prompt. drop it
        silent! unlet self.pending
        call remove(lines, -1)
      else
        " no trailing \n. Assume continuation will be sent in next block
        let self.pending = lines[-1]
        let lines[-1] = lines[-1].' ... waiting for \n'
      endif

      " let lines = map(lines, string('<: ').'.v:val')
      let lines = filter(lines, 'v:val != ""')
      if has_key(self,'regex_drop')
        let lines = filter(lines, 'v:val !~'.string(self.regex_drop))
      endif
      " call append('$', lines)
      "
      " if has_key(self, 'move_last'))
        " exec "normal G"
      " endif
      call async#AppendBuffer(self.bufnr, lines, has_key(self, 'move_last'))
    catch /.*/
      call append('$',v:exception)
    endtry
  endf
  fun! ctx.terminated()
    call async#AppendBuffer(self.bufnr, "exit code: ". self.status, 1)
  endf
  call async#Exec(ctx)
  return ctx
endf

" }}}

" implementation {{{ 1

fun! s:Select(name, p)
  return (a:p && g:async_implementation == 'auto') || a:name == g:async_implementation
endf

let s:async_helper_path = fnamemodify(expand('<sfile>'),':h:h').'/C/vim-addon-async-helper'
if s:Select('native', exists('*async_exec')) && !has('gui') 
  " Vim async impl
  for i in ['exec','kill','write','list']
    let s:impl[i] = function('async_'.i)
  endfor
  let s:impl['supported'] = 'native'

elseif s:Select('c_executable', 1) && executable(s:async_helper_path)

  " client-server callback is async#Receive
  let s:processes = {}
  let s:process_id = 1

  fun! s:impl.exec(ctx)
    let s:processes[s:process_id] = a:ctx
    " input_file2 will be moved to input_file
    " stdout_file is used to pass data back to Vim after async#Receive
    " notification
    let a:ctx.tmp_from_vim = tempname()
    let a:ctx.tmp_from_vim2 = tempname()
    let a:ctx.tmp_to_vim = tempname()
    " start background process
    let cmd = s:async_helper_path.' vim '.join(map([v:servername, s:process_id, a:ctx.tmp_from_vim, a:ctx.tmp_to_vim, a:ctx.cmd], 'shellescape(v:val)'),' ').'&'
    " let g:cmd = cmd
    call system(cmd)
    let s:process_id += 1
  endf
  fun! s:impl.kill(ctx)
    exec '!pkill '. a:ctx.pid
  endf
  fun! s:impl.write(ctx, input)
    if  (-1 == writefile(split(a:input,"\n",1), a:ctx.tmp_from_vim2, 'b'))
      echoe "writing vim to  tool file failed!"
    endif
    " mv so that its an atomic operation (make sure the process does't read a
    " half written file)
    call rename(a:ctx.tmp_from_vim2, a:ctx.tmp_from_vim)
    " wait until the proces removed the file
    let start_waiting = localtime()
    while (filereadable(a:ctx.tmp_from_vim))
      if localtime() - start_waiting > 10
        echoe "external helper process didn't read the input file !"
        " vim will clean up tmp file on shutdown
        return
      endif
    endw
  endf
  fun! s:impl.list()
    return s:processes
  endf

elseif s:Select('mzscheme', has('mzscheme'))

  " TODO (racket implementation ?)
  
elseif s:Select('python', has('python'))

  " TODO python implementation calling back into vim using client-server

endif

fun! async#Receive(processId, data)
  if !has_key(s:processes, a:processId)
    echoe "async#Receive called with unkown vim process identifier"
    return
  endif
  let ctx = s:processes[a:processId]
  let message = a:data[:0]
  let data = a:data[1:]
  if message == "p"
    let ctx.pid = 1 * data
    call ctx.started()
  elseif message == "d"
    " eval es evil .. but its the only way to preserve \r \n in input
    " because a tempname is used I think its ok
    call ctx.receive("stdout", eval(readfile(ctx.tmp_to_vim,'b')[0]))
    call delete(ctx.tmp_to_vim)
  elseif message == "k"
    let ctx.status = 1 * data
    call ctx.terminated()
  endif
endf

" documentation see README

" returns either "no" or the implementation being used
fun! async#Supported()
  return s:impl.supported
endf

fun! async#Exec(ctx)
  return s:impl.exec(a:ctx)
endf

fun! async#Kill(ctx)
  return s:impl.kill(a:ctx)
endf

fun! async#Write(ctx, input)
  return s:impl.write(a:ctx, a:input)
endf

fun! async#List()
  return s:impl.list()
endf
"
" does this make sense?
" fun! async#Read(ctx)
" endf


" }}}
