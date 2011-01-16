
" python interpreter implementation {{{1

" usage:
" call repl_python#PythonBuffer({'cmd':'irb','move_last' : 1})
" provides python completion. Be careful. If you do foo.remove().<c-x><c-o> 
" foo.remove() will be evaluated (multiple times!)
"
"
" [2]: TODO arity and documentation !? http://stackoverflow.com/questions/990016/how-to-find-out-the-arity-of-a-method-in-python
"
" You can also run /bin/sh and use require 'debug' in your ruby scripts
fun! repl_python#PythonBuffer(...)
  let ctx = a:0 > 0 ? a:1 : {}
  call async_porcelaine#LogToBuffer(ctx)
  call async#ExecInBuffer(ctx.bufnr, 'setlocal omnifunc=repl_python#PythonOmniComplete | setlocal completeopt=preview,menu,menuone')
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

let s:py_helper_fun_file = expand('<sfile>:h').'/py-helper-fun.py'

" return function which is used to generate the completion items
" This function is interpreted and run in the python interpreter
" Alse return the regex which intercepts the completion result
fun! repl_python#CompletionFunc()
  let imports = ['import inspect', 'import string']

  " see autoload/py-helper-fun.py
  let fun_code = readfile( s:py_helper_fun_file )+[]
  return { 'pattern' : '^>>> >>> '. repeat('\.\.\. ', len(fun_code)) .'>>> \(.*\)\n>>> ',
         \ 'py_code' : join(map(imports + fun_code, 'v:val.'.string("\n")),'') }
endf

" called with b:ctx context
fun! repl_python#HandlePythonCompletion(...) dict
  " add debug here for debugging
  call call(function("repl_python#HandlePythonCompletion2"), a:000, self)
endf

fun!  repl_python#HandlePythonCompletion2(data) dict

  " call append('$', string([self.completion_state, a:data]))
  call add(g:aaa, a:data)

  if self.completion_state == -1
    " receiving dir() result

    let match = matchlist(a:data, self.py_compl.pattern)

    " trick to make None known to Vim when evaluating result
    let None = "None"

    " result
    let self.completions = []
    " this is evil again
    let self.res = eval(match[1])
    for [type, name, doc, spec] in self.res
      let open = ''
      if len(spec) > 0 && len(eval(spec[0])) > 0
        let open = '('
      elseif doc =~ '^[^(]\+(' && doc !~ '^int(x[, base])\|str(object) -> string'
        let open = '('
      endif
      call add(self.completions, {'word': name.open, 'menu': string(spec),'info': name.": ".string(spec)."\n".substitute(doc, '\\n', "\n",'g') })
    endfor
    
    " restart completion
    call feedkeys(repeat("\<bs>",len(s:wait))."\<c-x>\<c-o>")
  endif

endf

fun! repl_python#PythonOmniComplete(findstart, base)

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

      " b:line is evaluated multiple times which is bad.
      
      let line = matchstr(b:line, '\%(> \)\?\zs.*\ze')
      " drop last '.'

      if line[-2:] == '["' || line[-2:] == "['"
        let b:ctx.completion_type = 'key'
        let b:ctx.thing = line[:-3]
        let b:ctx.completion_types = ['dict']
      elseif line[-1:] == '.'
        let b:ctx.completion_type = 'dir'
        let b:ctx.completion_types = ['dir']
        let b:ctx.thing = line[:-2]
      else
        " nothing before cursor? use global scope completion completion
        let b:ctx.completion_type = 'global'
        let b:ctx.completion_types = ['dict']
        let b:ctx.thing = "globals()"
      endif
      
      let b:ctx.py_compl = repl_python#CompletionFunc()
      call b:ctx.dataTillRegexMatchesLine(b:ctx.py_compl.pattern, funcref#Function(function('repl_python#HandlePythonCompletion'), {'self': b:ctx } ))
      call b:ctx.write(b:ctx.py_compl.py_code."\n"
        \ .'print func_info_x234('. b:ctx.thing .','.string(b:ctx.completion_types).')'."\n")

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
