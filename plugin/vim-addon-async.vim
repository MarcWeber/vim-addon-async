if !exists('g:async') | let g:async = {} | endif | let s:async = g:async

inoremap <buffer> \\async-magic <c-r>
noremap  <buffer> \\async-magic :

augroup VIM_ADDON_ASYNC
  au!
  autocmd CmdwinEnter * let g:async.in_cmd = 1
  autocmd CmdwinLeave * let g:async.in_cmd = 0 | call async#RunDelayedActions()
  autocmd WinEnter,InsertLeave * call async#RunDelayedActions()
augroup end

let g:async.in_cmd = 0
