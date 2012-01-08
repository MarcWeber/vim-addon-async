" different impls are possible:
" - async patch for Vim
" - scheme impl (which supports kind of cooperative threads)
" - python  or external C executable calling back into Vim using client-server
"   feature

" defined in plugin file
let s:async = g:async
let s:async.cmd_max_chars = get(s:async, 'cmd_max_chars', 2000)
let s:async.vim = get(s:async,'vim','vim')

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

" same as call. If function is a string or a list of strings they'll be
" executed instead
fun! async#Call(...)
  if type(a:1) == type('')
    exec a:1
  elseif type(a:1) == type([])
    for e in a:1 | exec e | endfor
  else
    return call(function('call'), a:000)
  endif
endf

" ... same as for function "call"
fun! async#ExecInBuffer(bufnr, ...)
  let this_win = winnr()
  let other = bufwinnr(a:bufnr)
  if other == -1
    " do actions in other buffor to not disturb the layout
    " TODO avoid splitting if buffer was open - use lazyredraw etc
    let old_tab = tabpagenr()
    tabnew
    exec 'b '.a:bufnr
    call call(function('async#Call'), a:000)
    q!
    if old_tab != tabpagenr()
      normal gT
    endif
  else
    " buffer is visibale. So move cursor there:
    exec other.'wincmd w'
    call call(function('async#Call'), a:000)
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
fun! async#GetLines()
  let current_line = line('.')
  if !exists('b:async_input_start') || b:async_input_start > current_line
    throw "can't determine lines to be sent to process. Select it lines visually (V) and press <cr>, please, or move cursor below '_' mark"
  endif
  return join(getline(b:async_input_start, current_line),"\n")
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
" ctx.kill([signal]) # kill the process. signal defaults to -9 which terminates the process
" ctx.signal('interrupt')
" ctx.write(data [, fd ] ) fd not implemented yet
"
" Some keys will be added depending on the implementation
fun! async#Exec(ctx)
  if has_key(a:ctx,'kill')
    throw "can't exec ctx twice (yet)"
  endif
  let ctx = a:ctx
  let ctx.vim_process_id = s:vim_process_id
  let s:vim_process_id += 1
  let s:async.processes[ctx.vim_process_id] = ctx

  " try finding supported implementation:
  let impl = get(ctx,'implementation', 'auto')
  if impl == 'auto'
    " native is disabled because work branch is not up to date (argument order
    " changed)
    if exists('*async_exec') && !has('gui_running')
      let impl = 'native'
    elseif has('clientserver') && v:servername != ''
       if !executable(s:async_helper_path) && 'y' == input('compile c helper application? [y] ','')
         exec '!gcc '.shellescape('-o').' '.shellescape(s:async_helper_path).' '.shellescape(s:async_helper_path.'.c')
         if v:shell_error != 0 | throw "compiling helper app failed" | endif
       endif
      let impl = "c_executable"
    else
      "          failure condition                 message
      let reasons = [
            \ [ !has('clientserver')            ,  "no way to execute process. Vim must be either patched or compiled with clientserver support" ],
            \ [ v:servername == ''              ,  "no severname provided. Please restart vim and use the --servername option" ],
            \ [ !executable(s:async_helper_path),  "Couldn't find vim-addon-async executable" ]
          \ ]
      let reasons = map(filter(reasons,'v:val[0]'), 'v:val[1]')
      if empty(reasons)
        throw "unexpected case"
      else
        throw "don't know how to execute processes asynchronously on this installation. Possible reasons: ".join(reasons, ', ')
      endif
    endif
  endif

  let ctx.implementation = impl

  " add missing functions to ctx depending to chosen implementation
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

    if !has_key(ctx, 'started')
      fun ctx.started()
      endf
    endif

    call async_exec(ctx)

  elseif impl == 'c_executable' " c_executable {{{2

    " input_file2 will be moved to input_file
    " stdout_file is used to pass data back to Vim after async#Receive
    " notification
    let ctx.tmp_from_vim = tempname()
    let ctx.tmp_from_vim2 = tempname()
    let ctx.tmp_to_vim = tempname()
    " start background process
    let cmd = s:async_helper_path.' '. s:async.vim .' '.join(map([v:servername, ctx.vim_process_id, ctx.tmp_from_vim, ctx.tmp_to_vim, s:async.cmd_max_chars, ctx.cmd], 'shellescape(v:val)'),' ')
    let ctx['log-c_executable'] = tempname()

    if 0 || get(ctx,'debug_process', 0)
      " why don't I see the debugging output in the buffer?
      " call async_porcelaine#LogToBuffer({'cmd':cmd, 'move_last':1, 'prompt': '^.*\$[$] '})
      call append('$', ['copy paste this into a shell', cmd])
    else
      call system(cmd. ' > '. ctx['log-c_executable'].'& 2&>1')
    endif

    fun ctx.kill(...)
      let signal = a:0 > 0 ? a:1 : '9'
      exec '!kill -'.signal.' '. self.pid
    endf

    fun ctx.write(input)
      " force list
      let input = type(a:input) == type("") ? [a:input] : a:input

      " quote \ which will be unquoted by c_executable. list items will be
      " quoted joined by '\0' byte
      let quoted = join(map(input, 'escape(v:val,''\'')'),'\0')
      if  (-1 == writefile(split(quoted,"\n",1), self.tmp_from_vim2, 'b'))
        echoe "writing vim to  tool file failed!"
      endif
      " mv so that its an atomic operation (make sure the process does't read a
      " half written file)
      call rename(self.tmp_from_vim2, self.tmp_from_vim)
      " wait until the proces removed the file
      let start_waiting = localtime()
      while (filereadable(self.tmp_from_vim))
        if localtime() - start_waiting > 3
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
fun! async#ReceiveNoTry(processId, message, data)
  if !has_key(s:async.processes, a:processId)
    echoe "async#Receive called with unkown vim process identifier"
    return
  endif
  let ctx = s:async.processes[a:processId]
  if a:message == "pid"
    let ctx.pid = 1 * a:data[0]
    call ctx.started()
  elseif a:message == "data"
    call ctx.receive(get(ctx,'zero_aware',0) ? a:data : join(a:data,"ZERO_BYTE"), 1)
  elseif a:message == "died"
    let ctx.status = 1 * a:data[0]
    call ctx.terminated()
    unlet s:async.processes[a:processId]
  endif
  redraw
endf

fun! async#Receive(processId, message, ...)
  if a:0 > 0
    let data = a:1
  else
    let ctx = s:async.processes[a:processId]
    let content = readfile(ctx.tmp_to_vim,'b')[0]
    let data = eval(content)
    call delete(ctx.tmp_to_vim)
  else
  endif
  try
    call async#ReceiveNoTry(a:processId, a:message, data)
  catch /.*/
    call append('$', v:exception)
  endtry
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
  let a:action['delay-when'] = get(a:action,'delay-when', []) + ["in-cmdbuf","non-normal","in-commandline"]
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
        \ || (delay == "non-normal" && (s:async.in_cmd || mode() != 'n'))
        \ || (delay == "in-commandline"  && mode() == 'c')
        \ || (delay[:13] == "buf-invisible:" && bufwinnr(1*delay[14:]) == -1)
          let run = 0
        endif
      endfor 
      if run
        " run action
        let idx = idx + 1
        try
          if has_key(action,'exec')
            exec action.exec
          else
            let args = [action.fun]
            call add(args, get(action,'args',[]))
            if has_key(action, 'self') | call add(args, action.self) | endif
            call call(function('call'), args)
          endif
        catch /.*/
          echoe "exception while running delayed action :".v:exception
        endtry
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
