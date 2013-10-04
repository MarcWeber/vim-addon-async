" php -a interpreter implementation {{{1
let s:async = g:async
let s:async.php_repl_complete_lhs = '<c-x><c-o>'

" usage:
" call repl_php#PHPBuffer({'cmd':'irb','move_last' : 1})
" provides ruby completion. Be careful. If you do foo.remove().<c-x><c-o> 
" foo.remove() will be evaluated (multiple times!)
"
" You can also run /bin/sh and use require 'debug' in your ruby scripts
fun! repl_php#PHPBuffer(...)
  let ctx = a:0 > 0 ? a:1 : {}
  call async_porcelaine#LogToBuffer(ctx)
  call async#ExecInBuffer(ctx.bufnr, "call vim_addon_completion#InoremapCompletions(g:async, [{ 'setting_keys' : ['php_repl_complete_lhs'], 'fun': 'repl_php#PHPOmniComplete'}])")
endf

fun! s:Match(s)
  return a:s =~ b:base || ( b:additional_regex != '' && a:s =~ b:additional_regex)
endf

let s:wait  = "please wait"

let s:php_helper_fun_file = expand('<sfile>:h').'/php-completion-helper.php'

" let g:php_prompt = '\%((rdb:\d\+) \|irb([^)]*):\d\+:\d\+>\)'

" called with b:ctx context
fun!  repl_php#HandlePHPCompletion(data) dict

  " call append('$', string([self.completion_state, a:data]))
  call add(g:aaa, a:data)

  let match = matchlist(a:data, self.php_match_result_and_prompt)

  if self.completion_state == -1
    let self.completion_state += 1

    " read list of methods

    " this is evil! but I'm too lazy to find a regex for parsing the list
    " result
    let self.completions = []
    if match[1] == 'null'
      echom 'completion returned null!'
      return
    endif
    let t = eval(match[1])
    for compl in t
      call add(self.completions, {'word': compl.name, 'menu': compl.description})
    endfor

    call feedkeys(repeat("\<bs>",len(s:wait))."\<c-x>\<c-o>")
  endif

endf

fun! repl_php#PHPOmniComplete(findstart, base)

  if a:findstart
    let [bc,ac] = vim_addon_completion#BcAc()
    let b:bc = bc
    let b:match_text = matchstr(bc, '\zs\%(\[[^[]*$\|->[^-]*\)$')
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

      " remove partial match, we want Ruby to complete everything in the
      " first place
      let line = line[:-(len(a:base)+1)]
      let b:line = line
      let b:ctx.completion_state = -1

      silent! unlet b:ctx.intercept

      " helper function registereing HandlePHPCompletion callback which
      " receives data until next scala> prompt is seen
      fun! b:ctx.intercept()
        " 1) echoed command
        " 2) result line(S)
        " 3) optional ruby debugger prompt + echoed command
        " 4) printed marker
        " 5) optional ruby debugger prompt
        let self.php_match_result_and_prompt = '\_.*\nCOMPLETION:\([^\n]*\)\nphp > '
        call self.dataTillRegexMatchesLine(self.php_match_result_and_prompt, funcref#Function(function('repl_php#HandlePHPCompletion'), {'self': b:ctx } ))
      endf

      call b:ctx.intercept()

      " b:line is evaluated multiple times which is bad.
      " drop first PHP
      let lines = join(readfile(s:php_helper_fun_file)[1:],"\n")

      let line = matchstr(b:line, '\zs.*\ze')

      if !has_key(b:ctx, 'compl_function_defined')
        call b:ctx.write(lines."\n")
        let b:ctx.compl_function_defined = 1
      endif
      call b:ctx.write('echo_completions('.line.');'."\n")

      call feedkeys(s:wait)

      return []
    else
      let completions = b:ctx.completions
      unlet b:ctx.completions
      " return completions
      let patterns = vim_addon_completion#AdditionalCompletionMatchPatterns(a:base
          \ , "ocaml_completion", { 'match_beginning_of_string': 1})
      let additional_regex = get(patterns, 'vim_regex', "")
      let b:additional_regex = additional_regex

      call filter(completions, 's:Match(v:val.word)')

      return completions
    endif
  endif

endf
" }}}

" vim:fdm=marker
