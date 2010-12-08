
" ruby (irb) interpreter implementation {{{1

" usage:
" call repl_ruby#RubyBuffer({'cmd':'irb','move_last' : 1})
" provides ruby completion. Be careful. If you do foo.remove().<c-x><c-o> 
" foo.remove() will be evaluated (multiple times!)
"
" You can also run /bin/sh and use require 'debug' in your ruby scripts
fun! repl_ruby#RubyBuffer(...)
  let ctx = a:0 > 0 ? a:1 : {}
  call async_porcelaine#LogToBuffer(ctx)
  call async#ExecInBuffer(ctx.bufnr, 'setlocal omnifunc=repl_ruby#RubyOmniComplete | setlocal completeopt=preview,menu,menuone')
  let ctx.marker = "RUBY_COMPLETION_ASSISTANCE_END"
endf

fun! s:Match(s)
  return a:s =~ b:base || ( b:additional_regex != '' && a:s =~ b:additional_regex)
endf

fun! s:DropBad(list)
  call filter(a:list, 'v:val !~ "scala>" && v:val != "" && v:val != "NEXT_NEXT_NEXT" && v:val !~ '. string(''))
endf

let s:wait  = "please wait"

" let g:ruby_prompt = '\%((rdb:\d\+) \|irb([^)]*):\d\+:\d\+>\)'

" called with b:ctx context
fun!  repl_ruby#HandleRubyCompletion(data) dict

  " call append('$', string([self.completion_state, a:data]))
  call add(g:aaa, a:data)

  let match = matchlist(a:data, self.ruby_match_result_and_prompt)

  if self.completion_state == -1
    let self.completion_state += 1

    " read list of methods

    " this is evil! but I'm too lazy to find a regex for parsing the list
    " result
    let self.completions = []
    for [name, arity] in eval(match[1])
      let info = ' arity: '. arity
      call add(self.completions, {'word': name.(arity > 0 ? '(' : ''), 'menu': info, 'info': name.' '. info})
    endfor
    
    call feedkeys(repeat("\<bs>",len(s:wait))."\<c-x>\<c-o>")

endf

fun! repl_ruby#RubyOmniComplete(findstart, base)

  if a:findstart
    let [bc,ac] = vim_addon_completion#BcAc()
    let b:bc = bc
    let b:match_text = matchstr(bc, '\zs[^#().[\]{}\''";:\t ]*$')
    let b:start = len(bc)-len(b:match_text)
    return b:start
  else
    if !has_key(b:ctx,'completions')
      " ask async process to provide completions

      let b:base = a:base

      let line = matchstr(b:ctx.cmd_line_regex, b:bc)
      if line == ''
        let line = b:bc
      endif
      " remove partial match, we want Ruby to complete everything in the
      " first place
      let line = line[:-(len(a:base)+1)]
      let b:line = line
      let b:ctx.completion_state = -1

      silent! unlet b:ctx.intercept

      " helper function registereing HandleRubyCompletion callback which
      " receives data until next scala> prompt is seen
      fun! b:ctx.intercept()
        let rdb = '\%((rdb:\d\+) \)\?'
        " 1) echoed command
        " 2) result line(S)
        " 3) optional ruby debugger prompt + echoed command
        " 4) printed marker
        " 5) optional ruby debugger prompt
        let self.ruby_match_result_and_prompt = 
              \ '^.\{-}\n'
              \ .'\(\_.\{-}\)\n'
              \ .rdb.'print :'. self.marker
              \ .'\n'. self.marker .'nil\n'
              \ . rdb
        call self.dataTillRegexMatchesLine(self.ruby_match_result_and_prompt, funcref#Function(function('repl_ruby#HandleRubyCompletion'), {'self': b:ctx } ))
      endf

      call b:ctx.intercept()

      " b:line is evaluated multiple times which is bad.
      
      let line = matchstr(b:line, '\%(> \)\?\zs.*\ze')
      call b:ctx.write(line.'methods.map{|n| [n.to_s, '.line.'method(n).arity] }'."\n". "print :". b:.ctx.marker ."\n")
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
