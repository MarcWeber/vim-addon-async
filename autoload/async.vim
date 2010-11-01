" different impls are possible:
" - async patch for Vim
" - scheme impl (which supports kind of cooperative threads)
" - python  or external C executable calling back into Vim using client-server
"   feature

" defined in plugin file
let s:async = g:async

if !exists('s:sync.processes')
  let s:async.processes = {}
  let s:vim_process_id = 1
endif

" preferred async implementation. See README
if !exists('g:async_implementation')
  let g:async_implementation = 'auto'
endif

let s:impl = {'supported': 'no'}

" tool {{{ 1

fun! async#ExecAllArgs(...)
  for e in a:000
    exec e
  endfor
endf

fun! async#ExecInBuffer(bufnr, function, ...)
  let this_win = winnr()
  let other = bufwinnr(a:bufnr)
  if other == -1
    " do actions in other buffor to not disturb the layout
    " TODO avoid splitting if buffer was open - use lazyredraw etc
    let old_tab = tabpagenr()
    tabnew
    exec 'b '.a:bufnr
    call call(a:function, a:000)
    q!
    if old_tab != tabpagenr()
      normal gT
    endif
  else
    " buffer is visibale. So move cursor there:
    exec other.'wincmd w'
    call call(a:function, a:000)
    exec this_win.'wincmd w'
  endif
endf

fun! async#AppendBuffer(lines, moveLast)
   call append('$', a:lines)
   if a:moveLast
     normal G
   endif
endf

let g:rec = []

" joins the lines meant to be sent to a process
" Eg this example assumes they all lines are prefixed by >
" example : async#GetLines('^>\zs.*\ze')
" Lines which have been executed are prefixed by ' ' so that they won't be
" executed a second time (some commands don't have a result)
fun! async#GetLines(prefix)
  let idx = line('.')
  let lines = []
  while getline(idx) =~ a:prefix
    let l = getline(idx)
    call add(lines, matchstr(l, a:prefix))
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
"
"   Example testing that appending to previous lines works correctly:
"   call async#LogToBuffer({'cmd':'sh -c "es(){ echo -n \$1; sleep 1; }; while read f; do echo \$f; es a; es b; es c; echo; done"', 'move_last':1})
"
"   call async#LogToBuffer({'cmd':'/bin/sh', 'move_last':1, 'prompt': '^.*\$[$] '})
"   then try running this:
"   yes | { es(){ echo -n $1; sleep 1; }; while read f; do echo $f; es a; es b; es c; echo; done; }
fun! async#LogToBuffer(ctx)
  let ctx = a:ctx
  sp | enew
  let ctx.bufnr = bufnr('%')
  let b:ctx = ctx
  let prefix = '> '
  exec 'noremap <buffer> o o'.prefix
  exec 'noremap <buffer> O O'.prefix
  exec 'inoremap <buffer> <cr> <cr>'.prefix
  exec 'noremap <buffer> <space><cr> :call<space>b:ctx.write(async#GetLines(''^'.prefix.'\zs.*\ze'')."\n")<cr>'
  exec 'inoremap <buffer> <space><cr> <esc>:call<space>b:ctx.write(async#GetLines(''^'.prefix.'\zs.*\ze'')."\n")<cr>'
  vnoremap <buffer> <cr> y:call<space>b:ctx.write(getreg('"'))<cr>

  fun! ctx.started()
    call async#ExecInBuffer(self.bufnr, function('async#AppendBuffer'), "pid: " .self.pid, 1)
  endf
  fun! ctx.receive(...)
    call async#DelayUntilNotDisturbing('process-pid'. self.pid, {'delay-when': ['buf-invisible:'. self.bufnr], 'fun' : self.delayed_work, 'args': a:000, 'self': self} )
  endf
  fun! ctx.delayed_work(text, ...)
    " try
      " debug output like this
      " call append('0', 'rec: '.substitute(substitute(a:text,'\r', '\\r','g'), '\n', '\\n','g'))

      " in rare cases it happens that a line is sent in two parts: eg "p" and "rint\n"
      " write the "p" to the last line, but remember that there was no trailing
      " \n by assigning it to pending.

      let lines = split(a:text, '[\r\n]\+', 1)
      if has_key(self, 'pending')
        " drop pending line, it will be readded with rest of line
        call async#ExecInBuffer(self.bufnr, function('async#ExecAllArgs'), "normal Gdd")
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
      call async#ExecInBuffer(self.bufnr, function('async#AppendBuffer'), lines, has_key(self, 'move_last'))
    " catch /.*/
    "  call append('$',v:exception)
    " endtry
  endf
  fun! ctx.terminated()
    call async#ExecInBuffer(self.bufnr, function('async#AppendBuffer'), ["exit code: ". self.status], has_key(self, 'move_last'))
  endf
  call async#Exec(ctx)
  return ctx
endf

" }}}

" implementation {{{ 1

let s:async_helper_path = fnamemodify(expand('<sfile>'),':h:h').'/C/vim-addon-async-helper'

fun! async#List()
  " native implementation also keeps track of a list (func async_list)
  return s:async.processes
endf

" ctx must have key "cmd"
" the following functions will be added:
"
" ctx.kill() # kill the process
" ctx.signal('interrupt')
" ctx.write(data [, fd ] ) fd not implemented yet
"
" Some keys will be added depending on the implementation
fun! async#Exec(ctx)
  let ctx = a:ctx
  let ctx.vim_process_id = s:vim_process_id
  let s:vim_process_id += 1
  let s:async.processes[ctx.vim_process_id] = ctx

  " try finding supported implementation:
  let impl = get(ctx,'implementation', 'auto')
  if impl == 'auto'
    " native is disabled because work branch is not up to date (argument order
    " changed)
    if 0 && exists('*async_exec') && !has('gui_running')
      let impl = 'native'
    elseif has('clientserver') && v:servername != ''
       if !executable(s:async_helper_path) && 'y' == input('compile c hepler application? [y] ','')
         exec '! gcc -o'. s:async_helper_path.' '.s:async_helper_path.'.c'
         if v:shell_error != 0 | throw "compiling helper app failed" | endif
       endif
      let impl = "c_executable"
    else
      throw "no way to execute process. You must either have a patched Vim or  v:servername, != '' && has('clientserver') && executable(".s:async_helper_path.") "
  endif

  let ctx.implementation = impl

  " add missing functions to ctx depending no chosen implementation
  if impl == 'native' " native {{{2

    fun ctx.kill()
      call async_kill(self)
    endf

    fun ctx.write(input)
      call async_write(self, a:input)
    endf

    " on termination we have to unregister the ctx from the list
    " So override the terminated callback:
    if has_key(ctx, 'terminated')
      let ctx.terminated_user = ctx.terminated
      unlet ctx.terminated
    endif
    fun ctx.terminated()
      if has_key(self,'terminated_user')
        call self.terminated_user()
      endif
      unlet s:async.processes[self.vim_process_id]
    endf

  elseif impl == 'c_executable' " c_executable {{{2

    " input_file2 will be moved to input_file
    " stdout_file is used to pass data back to Vim after async#Receive
    " notification
    let ctx.tmp_from_vim = tempname()
    let ctx.tmp_from_vim2 = tempname()
    " start background process
    let cmd = s:async_helper_path.' vim '.join(map([v:servername, ctx.vim_process_id, ctx.tmp_from_vim, ctx.cmd], 'shellescape(v:val)'),' ')
    let ctx['log-c_executable'] = tempname()
    " let g:cmd = cmd
    call system(cmd. ' &> '. ctx['log-c_executable'].'&')

    fun ctx.kill()
      exec '!kill -9 '. self.pid
    endf

    fun ctx.write(input)
      if  (-1 == writefile(split(a:input,"\n",1), self.tmp_from_vim2, 'b'))
        echoe "writing vim to  tool file failed!"
      endif
      " mv so that its an atomic operation (make sure the process does't read a
      " half written file)
      call rename(self.tmp_from_vim2, self.tmp_from_vim)
      " wait until the proces removed the file
      let start_waiting = localtime()
      while (filereadable(self.tmp_from_vim))
        if localtime() - start_waiting > 10
          echoe "external helper process didn't read the input file !"
          " vim will clean up tmp file on shutdown
          return
        endif
      endw
    endf

  endif " }}}

  return ctx
endf

" helper function c_executable
fun! async#Receive(processId, data)
  echoe "received"
  if !has_key(s:async.processes, a:processId)
    echoe "async#Receive called with unkown vim process identifier"
    return
  endif
  let ctx = s:async.processes[a:processId]
  let message = a:data[:0]
  let data = a:data[1:]
  if message == "p"
    let ctx.pid = 1 * data
    call ctx.started()
  elseif message == "d"
    call ctx.receive(data, 1)
  elseif message == "k"
    let ctx.status = 1 * data
    call ctx.terminated()
    unlet s:async.processes[a:processId]
  endif
  redraw
endf

" }}}

" delayed processing {{{1
" There are some states when you don't want any updates. Eg
" when editing in the command window.
"
" action: dict whith keys
"   - self (optional)
"   - args (optional)
"   - fun or exec
"   - delay-when:  list of conditions when the action should not be run.
"       "buf-invisible:bufnr"
"       "in-cmdbuf"
"       "in-insertmode"
"       (more to be added)
fun! async#DelayWhen(key, action)
  let dict = get(s:async,'delayed-actions',{})
  let s:async['delayed-actions'] = dict
  let list = get(dict, a:key, [])
  call add(list, a:action)
  let dict[a:key] = list
  call async#RunDelayedActions()
endf


fun! async#DelayUntilNotDisturbing(key, action)
  let a:action['delay-when'] = get(a:action,'delay-when', []) + ["in-cmdbuf","in-insertmode","in-commandline"]
  call async#DelayWhen(a:key, a:action)
endf

let s:in_rda = 0

" try running delayed actions
fun! async#RunDelayedActions()
  " don't call this func recursively
  if (s:in_rda) | return | endif

  let s:in_rda = 1
  let dict = get(s:async,'delayed-actions',{})
  for [k,delayed_list] in items(dict)
    let idx = 0
    while idx < len(delayed_list)
      let run = 1
      let action=delayed_list[idx]
      let delay = action['delay-when'][0]

      for delay in get(action, 'delay-when', [])
        if   (delay == "in-cmdbuf" && s:async.in_cmd)
        \ || (delay == "in-insertmode"  && mode() == 'i')
        \ || (delay == "in-commandline"  && mode() == 'c')
        \ || (delay[:13] == "buf-invisible:" && bufwinnr(1*delay[14:]) == -1)
          let run = 0
        endif
      endfor 
      if run
        " run action
        let idx = idx + 1
        if has_key(action,'exec')
          exec action.exec
        else
          let args = [action.fun]
          call add(args, get(action,'args',[]))
          if has_key(action, 'self') | call add(args, action.self) | endif
          call call(function('call'), args)
        endif
      else
        break
      endif
    endwhile
    " drop processed:
    if (idx > 0) | call remove(delayed_list, 0, min([idx -1, len(delayed_list) - 1])) | endif
    if empty(delayed_list)
      unlet dict[k]
    endif
  endfor
  let s:in_rda = 0
endf
