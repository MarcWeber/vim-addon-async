" logicblox interpreter implementation {{{1

" usage:
" call repl_logicblox#PythonBuffer({'cmd':'python','move_last' : 1})
" provides python completion. Be careful. If you do foo.remove().<c-x><c-o> 
" foo.remove() will be evaluated (multiple times!)
"
"
" [2]: TODO arity and documentation !? http://stackoverflow.com/questions/990016/how-to-find-out-the-arity-of-a-method-in-python

let s:prompt = 'lb\%(i\)\?[ ]\?.\{-}> '

" You can also run /bin/sh and use require 'debug' in your ruby scripts
fun! repl_logicblox#LogicbloxBuffer(...)
  let ctx = a:0 > 0 ? a:1 : {}

  let ctx.prompt = get(ctx, 'prompt', s:prompt)
  let ctx.cmd = get(ctx, 'cmd', 'socat exec:lb,pty -')

  fun ctx.ensure_trailing_dot(lines)
    let lines = a:lines
    if (lines !~ '\.[ \r\n]*$')
      echom 'warning: adding missing .'
      let lines .= '.'
    endif
    return lines
  endf

  fun ctx.exec(lines)
    call async_porcelaine#HistorySaveCmd('exec '.a:lines, a:lines)
    return self.send_command("exec '". self.ensure_trailing_dot(a:lines)."'\n", {'add_history' : 0})
  endf

  fun ctx.query(lines)
    call async_porcelaine#HistorySaveCmd('query '.a:lines, a:lines)
    return self.send_command("query '".self.ensure_trailing_dot(a:lines)."'\n", {'add_history' : 0})
  endf

  fun ctx.addblock(lines)
    call async_porcelaine#HistorySaveCmd('addblock '.a:lines, a:lines)
    return self.send_command("addblock '". self.ensure_trailing_dot(a:lines)."'\n", {'add_history' : 0})
  endf

  call async_porcelaine#LogToBuffer(ctx)
  call async#ExecInBuffer(ctx.bufnr, 'setlocal omnifunc=repl_logicblox#LogicbloxComplete | setlocal completeopt=preview,menu,menuone')
  let ctx.marker = "RUBY_COMPLETION_ASSISTANCE_END"

  vnoremap <buffer> e y:call<space>b:ctx.exec(getreg('"'))<cr>
  vnoremap <buffer> b y:call<space>b:ctx.addblock(getreg('"'))<cr>
  vnoremap <buffer> q y:call<space>b:ctx.query(getreg('"'))<cr>
  inoremap <buffer> <expr> <c-x><c-o> vim_addon_completion#CompleteUsing('repl_logicblox#LogicbloxComplete')
endf

fun! s:Match(s)
  return a:s =~ b:base || ( b:additional_regex != '' && a:s =~ b:additional_regex)
endf

fun! s:DropBad(list)
  call filter(a:list, 'v:val !~ "scala>" && v:val != "" && v:val != "NEXT_NEXT_NEXT" && v:val !~ '. string(''))
endf

let s:wait  = "please wait"

" called with b:ctx context
fun! repl_logicblox#HandlePythonCompletion(...) dict
  " add debug here for debugging
  call call(function("repl_logicblox#HandlePythonCompletion2"), a:000, self)
endf

" }}}

fun! repl_logicblox#LBHelpToCompletion(lines)
  let completions = []
  let state = "wait_command"

  " for convenience add additional completions
  let append = {}
  let append['create'] = [{"word" : "create --unique", 'menu' : 'create with unique name'}]
  let append['close']  = [{"word" : "close --destroy", 'menu' : 'close and destroy'}]
  let append['addblock']  = [{"word" : "addblock <doc>", 'menu' : 'start multiline doc'}]

  for l in a:lines
    let r_match_one_line =  '^    \([^ ]\+\) \+\(.*\)'
    let r_match_multi_line =  '    \([^ ]\+\)'
    let r_match_multi_comment =  '^                        \(.*\)'

    if state == "wait_multi"
      if l =~ r_match_multi_comment
        let li = matchlist(l, r_match_multi_comment)
        call add(multi_comment, li[1])
      else
        call add(completions, {'word': l[1], 'menu': join(multi_comment, " ") })
        let state = "wait_command"
      endif
    endif
    if state == "wait_command" && l =~ r_match_one_line
      let li = matchlist(l, r_match_one_line)
      call add(completions, {'word': li[1], 'menu': li[2] })
      if has_key(append, li[1])
        let completions += append[li[1]]
      endif
    elseif state == "wait_command" && l =~ r_match_multi_line
      let cmd = l[1]
      let state = "wait_multi"
      let multi_comment = []
    endif
    " export-protobuf     export protobuf message to a file
  endfor
  return completions
endf

fun! repl_logicblox#HandleCompletion(data) dict
  call add(g:aaa, a:data)

  let completions = self.completion_state.completions
  let receive_stack = self.completion_state.receive_stack
  let lines = split(a:data, "\r\n")

  if (receive_stack[0] == 'add_workspaces')
    for v in ['open ', 'delete ']
      let completions += map(lines[1:], '{"word": '.string(v).'.v:val}')
    endfor
  elseif (receive_stack[0] == 'lbi')
    let completions += map(lines, '{"word": v:val}')
  elseif (receive_stack[0] == 'lb')
    let b:ctx.help_completion = repl_logicblox#LBHelpToCompletion(lines)
    let completions += b:ctx.help_completion
  else
    throw "bad"
  endif
  call remove(receive_stack, 0)
  call repl_logicblox#FinishCompletion()
endf


" fun! repl_logicblox#NextCompletion()
"   let completions = b:ctx.completion_state.completions
"   let stack = b:ctx.completion_state.stack
" 
"   let data_then_prompt = '\(.*\)'.s:prompt
"   if len(b:ctx.completion_state.stack) == 0
"     call feedkeys(repeat("\<bs>",len(s:wait))."\<c-x>\<c-o>", "n")
"   else
" 
"     let next_ = stack[0]
" 
"     if next_ == 'add_workspaces'
"       call b:ctx.dataTillRegexMatchesLine(data_then_prompt, funcref#Function(function('repl_logicblox#HandleCompletion'), {'self': b:ctx } ))
"       call b:ctx.write("workspaces\n")
"     elseif next_ == 'lb'
"       if (has_key(b:ctx, 'help_completion'))
"         let completions += b:ctx.help_completion
"         call remove(stack, 0)
"         call repl_logicblox#NextCompletion()
"       else
"         call b:ctx.dataTillRegexMatchesLine(data_then_prompt, funcref#Function(function('repl_logicblox#HandleCompletion'), {'self': b:ctx } ))
"         call b:ctx.write("help\n")
"       endif
"     elseif b:ctx.completion_state.stack[0] == 'lbi'
"       call b:ctx.dataTillRegexMatchesLine(data_then_prompt, funcref#Function(function('repl_logicblox#HandleCompletion'), {'self': b:ctx } ))
"       call b:ctx.write("list\n")
"     endif
"   endif
" endf


fun! repl_logicblox#NextCompletion()
  let send_stack = b:ctx.completion_state.send_stack
  let b:ctx.completion_state.receive_stack += send_stack
  let b:ctx.completion_state.send_stack = []

  let data_then_prompt = '\(.\{-}\)'.s:prompt
  for next_ in send_stack
    if next_ == 'add_workspaces'
      call b:ctx.dataTillRegexMatchesLine(data_then_prompt, funcref#Function(function('repl_logicblox#HandleCompletion'), {'self': b:ctx } ))
      call b:ctx.write("workspaces\n")
    elseif next_ == 'lb'
      call b:ctx.dataTillRegexMatchesLine(data_then_prompt, funcref#Function(function('repl_logicblox#HandleCompletion'), {'self': b:ctx } ))
      call b:ctx.write("help\n")
    elseif next_ == 'lbi'
      call b:ctx.dataTillRegexMatchesLine(data_then_prompt, funcref#Function(function('repl_logicblox#HandleCompletion'), {'self': b:ctx } ))
      call b:ctx.write("list\n")
    endif
  endfor
endf

fun! repl_logicblox#FinishCompletion()
  let receive_stack = b:ctx.completion_state.receive_stack
  if len(receive_stack) == 0
    call feedkeys(repeat("\<bs>",len(s:wait))."\<c-x>\<c-o>", "n")
  endif
endf

fun! repl_logicblox#LogicbloxComplete(findstart, base)
  if a:findstart
    let [bc,ac] = vim_addon_completion#BcAc()
    let b:bc = bc
    let b:match_text = matchstr(bc, '\zs[^#().[\]{}\''";\t ]*$')
    let b:start = len(bc)-len(b:match_text)
    return b:start
  else
    if !has_key(b:ctx, 'completion_state')
      " ask async process to provide completions
      let b:base = a:base
      let line = b:bc
      if line == ''
        let line = b:bc
      endif
      let b:ctx.line = line[:-(len(a:base)+1)]
      if has_key(b:ctx, 'last_prompt') && b:ctx.last_prompt =~ 'lb [^>]'
        let b:ctx.completion_state = {'receive_stack' : [], 'send_stack' :  ['lbi', 'lb', 'add_workspaces'], 'completions' : []}
        call repl_logicblox#NextCompletion()
      else
        " tkkkjjjkjkk/epletion?
        let b:ctx.completion_state = {'receive_stack' : [], 'send_stack': ['lb', 'add_workspaces'], 'completions' : []}
        call repl_logicblox#NextCompletion()
      endif
      call feedkeys(s:wait)

      return []
    else
      let completions = b:ctx.completion_state.completions
      unlet b:ctx.completion_state

      let b:additional_regex = ''
      call filter(completions, 'v:val.word =~ b:base')
      let g:compl = completions
      return completions
    endif
  endif

endf

" vim:fdm=marker
