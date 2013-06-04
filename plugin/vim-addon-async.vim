if !exists('g:async') | let g:async = {} | endif | let s:c = g:async
let s:c.line_prefix = get(s:c,'line_prefix', '> ')

" shell like history file:
let s:c.async_history_file = get(s:c,'async_history_file',expand('~/.vim-addon-async-history'))
let s:c.async_history_length = get(s:c,'async_history_length', 1000)

inoremap <buffer> \\async-magic <c-r>
noremap  <buffer> \\async-magic :

augroup VIM_ADDON_ASYNC
  au!
  autocmd CmdwinEnter * let g:async.in_cmd = 1
  autocmd CmdwinLeave * let g:async.in_cmd = 0 | call async#RunDelayedActions()
  autocmd WinEnter,InsertLeave * call async#RunDelayedActions()
augroup end

let g:async.in_cmd = 0

sign define async_input_start text=_ linehl=


" I'm not quite happy yet - too much delay.
command! AsyncGrepR  call async_porcelaine#MakeOrGrep('grep -nr '.shellescape(input('word: ')).' .')
command! AsyncGrepRI call async_porcelaine#MakeOrGrep('grep -nr '.shellescape(input('word: ')).' .')
command! AsyncMake call async_porcelaine#MakeOrGrep(input('cmd: ', 'make '))
