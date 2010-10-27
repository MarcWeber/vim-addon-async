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

" example:
" call async#LogToBuffer({'cmd':'python -i', 'move_last':1, 'regex_drop': '^>>>$'})
" call async#LogToBuffer({'cmd':'scala','move_last':1, 'regex_drop': 'scala> $'})
"
" This is still not perfect Sometimes a line is split ..
fun! async#LogToBuffer(ctx)
  let ctx = a:ctx
  let ctx['bufnr'] = bufnr('%')
  sp
  let b:ctx = ctx
  noremap <buffer> <space><cr> :call<space>async#Write(b:ctx, getline('.')."\n")<cr>
  inoremap <buffer> <space><cr> <esc>:call<space>async#Write(b:ctx, getline('.')."\n")<cr>
  fun! ctx.started()
    call async#AppendBuffer(self.bufnr, "pid: " .self.pid)
  endf
  fun! ctx.receive(type, text)
    " call append('$', 'rec: '.substitute(substitute(a:text,'\r', '\\r','g'), '\n', '\\n','g'))
    let lines = split(a:text, '[\r\n]\+')
    let lines = map(lines, string('out: ').'.v:val')
    let lines = filter(lines, 'v:val != ""')
    " call async#AppendBuffer(self.bufnr, lines)
    if has_key(self,'regex_drop')
      let lines = filter(lines, 'v:val !~'.string(self.regex_drop))
    endif
    call append('$', lines)
    if has_key(self,'move_last')
      exec "normal G"
    endif
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
