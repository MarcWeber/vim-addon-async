" different impls are possible:
" - async patch for Vim
" - scheme impl (which supports kind of cooperative threads)
" - python  or external C executable calling back into Vim using client-server
"   feature

if !exists('g:async_implementation')
  let g:async_implementation = 'auto'
endif

let s:impl = {'supported': 'no'}

fun! s:Select(name, )
  return (a:p && g:async_implementation == 'auto') || a:name == g:async_implementation
endf

if s:Select('native', exists('g:async_exec'))

  " Vim async impl
  for i in ['exec','kill','write','list']
    let s:impl[i] = function('asystem_'.$i)
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
  return s:impl.exec(a:ctx);
endf

fun! async#Kill(ctx)
  return s:impl.kill(a:ctx);
endf

fun! async#Write(ctx)
  return s:impl.write(a:ctx);
endf

fun! async#List(ctx)
  return s:impl.list(a:ctx);
endf

" does this make sense?
" fun! async#Read(ctx)
" endf
