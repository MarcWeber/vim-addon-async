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

fun! async#AppendBuffer(bnr, lines)
  if 0 && exists('*withcurrentbuffer')
    call withcurrentbuffer(a:bnr, function('append'), [a:lines])
   else
     " TODO avoid splitting if buffer was open - use lazyredraw etc
     sp
     exec 'b '.a:bnr
     call append('$', a:lines)
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
  let ctx['bufnr'] = bufnr('%')
  sp
  let b:ctx = ctx
  let prefix = '> '
  exec 'noremap <buffer> o o'.prefix
  exec 'noremap <buffer> O O'.prefix
  exec 'inoremap <buffer> <cr> <cr>'.prefix
  exec 'noremap <buffer> <space><cr> :call<space>async#Write(b:ctx, async#GetLines(''^'.prefix.'\zs.*\ze'')."\n")<cr>'
  exec 'inoremap <buffer> <space><cr> <esc>:call<space>async#Write(b:ctx, async#GetLines(''^'.prefix.'\zs.*\ze'')."\n")<cr>'
  fun! ctx.started()
    call async#AppendBuffer(self.bufnr, "pid: " .self.pid)
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
        call remove(lines, -1)
      else
        " no trailing \n. Assume continuation will be sent in next block
        let self.pending = lines[-1]
        let lines[-1] = lines[-1].' ... waiting for \n'
      endif

      " let lines = map(lines, string('<: ').'.v:val')
      let lines = filter(lines, 'v:val != ""')
      " call async#AppendBuffer(self.bufnr, lines)
      if has_key(self,'regex_drop')
        let lines = filter(lines, 'v:val !~'.string(self.regex_drop))
      endif
      call append('$', lines)
      if has_key(self,'move_last')
        exec "normal G"
      endif
    catch /.*/
      call append('$',v:exception)
    endtry
  endf
  fun! ctx.terminated()
    call async#AppendBuffer(self.bufnr, "exit code: ". self.status)
  endf
  call async#Exec(ctx)
  return ctx
endf

" }}}

" implementation {{{ 1
fun! s:Select(name, p)
  return (a:p && g:async_implementation == 'auto') || a:name == g:async_implementation
endf

if s:Select('native', exists('*async_exec'))

  " Vim async impl
  for i in ['exec','kill','write','list']
    let s:impl[i] = function('async_'.i)
  endfor
  let s:impl['supported'] = 'native'

elseif s:Select('mzscheme', has('mzscheme'))

  " TODO (racket implementation ?)
  
elseif s:Select('python', has('python'))

  " TODO python implementation calling back into vim using client-server

elseif s:Select('c_executable', 0)

  " TODO external c helper app implementation calling back into vim using client-server

endif

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

fun! async#List(ctx)
  return s:impl.list(a:ctx)
endf
"
" does this make sense?
" fun! async#Read(ctx)
" endf


" }}}
