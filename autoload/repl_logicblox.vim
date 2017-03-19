" logicblox interpreter implementation {{{1

" usage:
" call repl_logicblox#PythonBuffer({'cmd':'python','move_last' : 1})
" provides python completion. Be careful. If you do foo.remove().<c-x><c-o> 
" foo.remove() will be evaluated (multiple times!)
"
"
" [2]: TODO arity and documentation !? http://stackoverflow.com/questions/990016/how-to-find-out-the-arity-of-a-method-in-python

let s:prompt = 'lb\%(i\)\?[ ]\?.*> '

" You can also run /bin/sh and use require 'debug' in your ruby scripts
fun! repl_logicblox#LogicbloxBuffer(...)
  let ctx = a:0 > 0 ? a:1 : {}

  let ctx.prompt = get(ctx, 'prompt', s:prompt)
  let ctx.cmd = get(ctx, 'cmd', 'socat exec:lb,pty -')

  fun ctx.exec(lines)
    return self.send_command("exec '".a:lines."'\n")
  endf

  fun ctx.query(lines)
    return self.send_command("query '".a:lines."'\n")
  endf

  fun ctx.addblock(lines)
    return self.send_command("addblock '".a:lines."'\n")
  endf

  call async_porcelaine#LogToBuffer(ctx)
  call async#ExecInBuffer(ctx.bufnr, 'setlocal omnifunc=repl_logicblox#LogicbloxComplete | setlocal completeopt=preview,menu,menuone')
  let ctx.marker = "RUBY_COMPLETION_ASSISTANCE_END"

  vnoremap <buffer> e y:call<space>b:ctx.exec(getreg('"'))<cr>
  vnoremap <buffer> b y:call<space>b:ctx.block(getreg('"'))<cr>
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

let g:lb_prompt = 'lb> '

" called with b:ctx context
fun! repl_logicblox#HandlePythonCompletion(...) dict
  " add debug here for debugging
  call call(function("repl_logicblox#HandlePythonCompletion2"), a:000, self)
endf

" }}}

fun! repl_logicblox#LBHelpToCompletion(lines)
  let state = "wait_command"
  let completions = []
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

  let lines = split(a:data, "\r\n")

  let add_workspaces_on_regex = {'^op' : 'open ', '^del' : 'delete '}

  if self.completion_state == -1
    if (b:ctx.completion_stack[0] == 'add_workspaces')
      for [k,v] in items(add_workspaces_on_regex)
        if b:match_text =~ k
          let b:ctx.completions += map(lines, '{"word": '.string(v).'.v:val}')
        endif
      endfor
    elseif (b:ctx.completion_stack[0] == 'lbi')
      let b:ctx.completions = map(lines, '{"word": v:val}')
    elseif (b:ctx.completion_stack[0] == 'lb')
      let b:ctx.completions = repl_logicblox#LBHelpToCompletion(lines)
      for [k,v] in items(add_workspaces_on_regex)
        if b:match_text =~ k
          let b:ctx.completion_stack = ['add_workspaces']
          call b:ctx.dataTillRegexMatchesLine('\(.*\)lb> ', funcref#Function(function('repl_logicblox#HandleCompletion'), {'self': b:ctx } ))
          call b:ctx.write("workspaces\n")
          return
        endif
      endfor
    else
      throw "bad"
    endif
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
    if !has_key(b:ctx,'completions')
      " ask async process to provide completions
      let b:base = a:base
      let line = b:bc
      if line == ''
        let line = b:bc
      endif
      let b:ctx.line = line[:-(len(a:base)+1)]
      echom b:ctx.line
      let b:ctx.completion_state = -1

      if has_key(b:ctx, 'last_prompt') && b:ctx.last_prompt =~ '^lbi'
        let b:ctx.completion_stack = ['lbi']
        call b:ctx.dataTillRegexMatchesLine('\(.*\)'.s:prompt, funcref#Function(function('repl_logicblox#HandleCompletion'), {'self': b:ctx } ))
        call b:ctx.write("list\n")
      else
        " tkkkjjjkjkk/epletion?
        let b:ctx.completion_stack = ['lb']
        call b:ctx.dataTillRegexMatchesLine('\(.*\)lb> ', funcref#Function(function('repl_logicblox#HandleCompletion'), {'self': b:ctx } ))
        call b:ctx.write("help\n")
      endif
      call feedkeys(s:wait)

      return []
    else
      let completions = b:ctx.completions
      unlet b:ctx.completions
      let b:additional_regex = ''
      call filter(completions, 'v:val.word =~ b:base')
      let g:compl = completions
      return completions
    endif
  endif

endf

" vim:fdm=marker
