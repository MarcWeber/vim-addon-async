if !exists('g:async') | let g:async = {} | endif | let s:c = g:async

" HISTORY implementation {{{1
fun! async_porcelaine#LoadHistory()
  return filereadable(s:c.async_history_file)
        \ ?  eval(readfile(s:c.async_history_file, 'b')[0])
        \ : []
endf

fun! async_porcelaine#HistorySaveCmd(async_cmd, commandline)
  let lines = [[a:commandline, a:async_cmd]] + async_porcelaine#LoadHistory()[:s:c.async_history_length]
  call writefile([string(lines)], s:c.async_history_file, 'b')
endf

fun! async_porcelaine#CommandFromHistory()
  let history = async_porcelaine#LoadHistory()
  let item = tlib#input#List('si', 'select history line to be appended'
        \, map(copy(history),"substitute(v:val[0], \"\\n\",'|','g').' cmd: '.(v:val[1])"))
  call append('$', split(history[item-1][0],"\n"))
endf
" }}}

" only call receive after full line has been received
" one line will be passed each time
" usage see autoload/vim_addon_async_tests.vim
fun! async_porcelaine#LineBuffering(ctx)
  let ctx = a:ctx
  let ctx.original_receive = ctx.receive
  unlet ctx.receive
  fun ctx.receive(data,...)
    let lines = split(get(self,'buffer','') . a:data, "\n", 1)
    for l in lines[0:-2]
      call call(self.original_receive, [l], self)
    endfor
    let self.buffer = lines[-1]
  endf
endf

" run an interpreter (eg python, scala, ..), dropping the prompt.
" This function also handles incomplete lines.
" 
" All lines starting with '> ' will be passed to the interpreter.
" type o to start writing a line, type <space><cr> to sent it.
"
" examples:
"   call async_porcelaine#LogToBuffer({'cmd':'python -i', 'move_last':1, 'prompt': '^>>> $'})
"   call async_porcelaine#LogToBuffer({'cmd':'scala','move_last':1, 'prompt': 'scala> $'})
"
"   Example testing that appending to previous lines works correctly:
"   call async_porcelaine#LogToBuffer({'cmd':'sh -c "es(){ echo -n \$1; sleep 1; }; while read f; do echo \$f; es a; es b; es c; echo; done"', 'move_last':1})
"
"   call async_porcelaine#LogToBuffer({'cmd':'/bin/sh -i', 'move_last':1, 'prompt': '^.*\$[$] '})
"   then try running this:
"   yes | { es(){ echo -n $1; sleep 1; }; while read f; do echo $f; es a; es b; es c; echo; done; }
fun! async_porcelaine#LogToBuffer(ctx)
  let ctx = a:ctx

  if has_key(ctx, 'terminated')
    let ctx.terminated_overwritten = ctx.terminated
  endif

  let buf_name = get(ctx, 'buf_name', '')

  let new_buf = "sp | exec ' new '.(buf_name == '' ? '' : ' '.fnameescape(buf_name))"
  if buf_name != '' && bufnr(buf_name) >= 0
    exec 'b '.bufnr(buf_name)
    if !has_key(b:ctx,'status')
      throw "buffer ".buf_name." already exists and process is running. Stop it by ctrl-c, then retry!"
    else
      " reuse buf
    endif
  else
    exec new_buf
    setlocal noswapfile
    setlocal buftype=nofile
  endif
  let ctx.bufnr = bufnr('%')
  let b:ctx = ctx
  let ctx.pending = "\n"
  " list of functions which will get data before it will be processed the
  " normal way. It must process the data it can handle and return 0 if it
  " wants more or the rest if its done and got too many characters
  let ctx.interceptors = []
  noremap <buffer> <c-c> :call b:ctx.kill('SIGINT')<cr>
  exec 'noremap <buffer> <space><cr> :call<space>b:ctx.send_command(async#GetLines()."\n")<cr>'
  exec 'inoremap <buffer> <space><cr> <esc>:call<space>b:ctx.send_command(async#GetLines()."\n")<cr>'
  vnoremap <buffer> <cr> y:call<space>b:ctx.send_command(getreg('"'))<cr>
  noremap <buffer> <c-h> :call async_porcelaine#CommandFromHistory()<cr>
  inoremap <buffer> <c-h> <esc>:call async_porcelaine#CommandFromHistory()<cr>a

  inoremap <buffer> <expr> <c-x><c-h> vim_addon_completion#CompleteUsing('async_porcelaine#HistoryComplete')

  augroup VIM_ADDON_ASYNC_AUTO_KILL
    " looks like this is not working because vim already hase dropped
    " b:ctx.kill .. could be keeping global list .. and delete the one which
    " is "missing" now ..
    autocmd BufUnload <buffer> call b:ctx.kill()
  augroup end

  fun! ctx.started()
    call async#ExecInBuffer(self.bufnr, function('async#AppendBuffer'), ["pid: " .self.pid. ", bufnr: ". self.bufnr, 1])
  endf
  let ctx.receive = function('async_porcelaine#Receive')

  " interception implementation (get data until a regex matches) 
  let ctx.interceptImpl = function('async_porcelaine#InterceptIpml')
  fun! ctx.dataTillRegexMatchesLine(regex, callback, ...)
    let self_ = a:0 > 0 ? a:1 : self
    call add(self.interceptors, funcref#Function(self.interceptImpl, {'args': [a:regex, a:callback], 'self': self_}))
  endf
  " }}}2
  
  fun! ctx.send_command(s, ...)
    let opts = a:0 > 0 ? a:1 : {}
    if get(opts, 'add_history', 1)
      call async_porcelaine#HistorySaveCmd(self.cmd, a:s)
    endif
    " force result appearing on a new line
    let self.pending = "\n"
    call self.write(a:s)
  endf

  let g:aaa= []

  fun! ctx.delayed_work(...)
    call call(self.delayed_work2, a:000, self)
  endf

  " default implementation: Add data to the buffer {{{2
  fun! ctx.delayed_work2(text, ...)
    call add(g:aaa, a:text)

    " try
      " debug output like this
      " call append('0', 'rec: '.substitute(substitute(a:text,'\r', '\\r','g'), '\n', '\\n','g'))

      " in rare cases it happens that a line is sent in two parts: eg "p" and "rint\n"
      " write the "p" to the last line, but remember that there was no trailing
      " \n by assigning it to pending.

      " this version is terrific slow let lines = split(get(self,'pending','').a:text, '[\r\n]\+', 1)
      let lines = split(substitute( get(self,'pending','').a:text, "\r\\%\\(\n\\)\\?", "\n", 'g'), '\n', 1)
      silent! unlet self.pending
      if lines[-1] == '' || (has_key(self, 'prompt') && lines[-1] =~ self.prompt)
        let self.last_prompt = lines[-1]
        " force adding \n when reply arrives after user has typed prompt
        let self.pending = "\n"
        call remove(lines, -1)
      endif

      " let lines = map(lines, string('<: ').'.v:val')
      " let lines = filter(lines, 'v:val != ""')
      if has_key(self,'regex_drop')
        let lines = filter(lines, 'v:val !~'.string(self.regex_drop))
      endif
      
      let p = get(self, 'line_prefix', s:c.line_prefix)
      if p != ''
        " don't map first line
        let lines = [lines[0]] + map(lines[1:], string(p).'.v:val')
      endif
      call async#ExecInBuffer(self.bufnr, function('async_porcelaine#AppendBuffer'), [lines, has_key(self, 'move_last')])
    " catch /.*/
    "  call append('$',v:exception)
    "  call append('$',v:throwpoint)
    " endtry
  endf
  " }}}

  fun! ctx.terminated()
    call async#ExecInBuffer(self.bufnr, function('async#AppendBuffer'), [ ["exit code: ". self.status], has_key(self, 'move_last')])
    if has_key(self, 'terminated_overwritten')
      call self.terminated_overwritten()
    endif
  endf
  call async#Exec(ctx)
  if (has_key(ctx, 'log-c_executable'))
    exec 'command! -buffer AsyncCExecutablelog :sp '. ctx['log-c_executable']
  endif
  return ctx
endf


fun! async_porcelaine#AppendBuffer(lines, moveLast)
  " first line is always appended to last line of buffer because not each
  " chunk of bytes contains a trailing \n
  let append_last = get(a:lines, 0, '')
  if append_last != ''
    call setline('$', getline('$').append_last)
  endif

  call append('$', a:lines[1:])
  if a:moveLast
    normal G
  endif

  let b:async_input_start = line('$')+1

  call vim_addon_signs#Push("async_input_start", [[bufnr('%'), b:async_input_start-1, 'async_input_start']] )

endf

fun! async_porcelaine#Receive(...) dict
  call call(function('async_porcelaine#Receive2'), a:000, self)
endf
fun! async_porcelaine#Receive2(...) dict
  let args = copy(a:000)
  while len(self.interceptors) > 0 && len(args[0] > 0)
    " call append('$', 'intercept mit '.string(args))
    let r = funcref#Call(self.interceptors[0], args, self)
    " call append('$', 'ret' . string(r))

    if type(r) == type("")
      call remove(self.interceptors,0,0)
      let args[0] = r
    elseif type(r) == type(0) && r == 0
      let args[0] = ""
      break
    endif
  endwhile

  " default action: append data to buffer
  if empty(self.interceptors) && len(args[0]) > 0
    call async#DelayUntilNotDisturbing('process-pid'. self.pid, {'delay-when': ['buf-invisible:'. self.bufnr], 'fun' : self.delayed_work, 'args': args, 'self': self} )
  endif
endf

fun! async_porcelaine#InterceptIpml(regex, callback, data, ...) dict
  let self.received_data = get(self,'received_data','').a:data
  let m = matchlist( self.received_data, a:regex )
  let first = empty(m) ? '' : m[0]

  if first == ""
    return 0
  else
    call funcref#Call(a:callback, [first])
    let r = self.received_data[len(first):]
    unlet self.received_data
    return r
  endif
endf

" scala interpreter implementation {{{1

" even provides completion support
" if you type \t the name will be completed
" if you type \t\t then you'll get the type
" This code belowe tries to catch that data
"
" Because we can't block the first time no results are returned.
" when getting completion data finished the completion is restarted
"
" This or something similar could be implemented for other interpreters as
" well.
"
" Beacuse \t\t is that slow its only used if there are up to 3 matches
" The real fix would be patching Scala (?)

" usage:
" call async_porcelaine#ScalaBuffer()
fun! async_porcelaine#ScalaBuffer(...)
  let ctx = a:0 > 0 ? a:1 : {}
  call extend(ctx, {'cmd':'scala','move_last':1, 'prompt': '^scala> $'}, 'keep')
  call async_porcelaine#LogToBuffer(ctx)
  call async#ExecInBuffer(ctx.bufnr, 'setlocal omnifunc=async_porcelaine#ScalaOmniComplete| setlocal completeopt=preview,menu,menuone')
endf

fun! s:Match(s)
  return a:s =~ b:base || ( b:additional_regex != '' && a:s =~ b:additional_regex)
endf

fun! s:DropBad(list)
  call filter(a:list, 'v:val !~ "scala>" && v:val != "" && v:val != "NEXT_NEXT_NEXT" && v:val !~ '. string(''))
endf

let s:wait  = "please wait"

" called with b:ctx context
fun! async_porcelaine#HandleScalaCompletionData(data) dict

  " call append('$', string([self.completion_state, a:data]))
  call add(g:aaa, a:data)

  if self.completion_state == -1
    let self.completion_state += 1

    " first scala result only contains names:

    let self.completions = []
    " first line is repeated cmd line - drop it
    let self.completion_names = split(a:data,"\n")[1:]

    " throw away lines which seem to be bad:
    call s:DropBad(self.completion_names)

    " many names are given in one line, split them
    let self.completion_names = split(join(self.completion_names," "),'\s\+')

    " keep only names you're interested in
    let self.completion_names = filter(self.completion_names, 's:Match(v:val)')
    " call append('$', 'names : '.len(self.completion_names).string(self.completion_names))

    if len(self.completion_names) > 3
      " without type
      for i in self.completion_names
        call add(self.completions, { 'word': i })
      endfor
      call feedkeys(repeat("\<bs>",len(s:wait))."\<c-x>\<c-o>")
    else
      " with type (experimental - untested)
      " get type information for everything
      let s = ''
      for t in self.completion_names
        if t == '' || t =~ 'H^' | continue | endif
        " 21 is ctrl-u which clears command line
        let s .= b:line.t."\t\t".nr2char(21)."println(\"NEXT_NEXT_NEXT\")\n"
        " these intercept calls should run code [1]
        call self.intercept()
      endfor
      call self.write(s)
    endif

  else
    " [1]

    let x = split(a:data,"\n")
    call s:DropBad(x)
    let t = join(x,"\n")
    " call append('$', 't: '.t.' erwartet :')

    " incermentation will be done on NEXT_NEXT_NEXT
    call add(self.completions, { 'word': self.completion_names[self.completion_state], 'info': t, 'menu': t})

    if self.completion_state == len(self.completion_names)-1
      " got all, restart completion
      call feedkeys(repeat("\<bs>",len(s:wait))."\<c-x>\<c-o>")
    else
      " call append('$', self.completion_state)
      " redraw
    endif

    let self.completion_state +=1

  endif

endf


fun! async_porcelaine#HistoryComplete(findstart, base)
  if a:findstart
    let [bc,ac] = vim_addon_completion#BcAc()
    let b:bc = bc
    let b:match_text = matchstr(bc, '\zs[^#().[\]{}\''";:\t ]*$')
    let b:start = len(bc)-len(b:match_text)
    return b:start
  else
    let b:base = a:base
    let line = b:bc
    let history = async_porcelaine#LoadHistory()
    let completions = []
    for x in history
      if x[0] =~ '^'.line
        let cmd = substitute(substitute(x[0], nr2char(10).'$', '', ''), nr2char(10), "\n", 'g')
        call add(completions, {'word': cmd, 'abbr': len(cmd) > 80 ? cmd[0:80].'...' : cmd, 'info' : cmd, 'menu': x[1] })
      endif
    endfor
    return completions
  endif
endf

fun! async_porcelaine#ScalaOmniComplete(findstart, base)

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

      let line = b:bc
      if line == ''
        let line = b:bc
      endif
      " remove partial match, we want Scala to complete everything in the
      " first place
      let line = line[:-(len(a:base)+1)]
      let b:line = line
      let b:ctx.completion_state = -1

      silent! unlet b:ctx.intercept

      " helper function registereing HandleScalaCompletionData callback which
      " receives data until next scala> prompt is seen
      fun! b:ctx.intercept()
        call self.dataTillRegexMatchesLine('.\{-}\nNEXT_NEXT_NEXT\n\n', funcref#Function(function('async_porcelaine#HandleScalaCompletionData'), {'self': b:ctx } ))
      endf

      call b:ctx.intercept()
      call b:ctx.write(b:line."\t.".nr2char(21))
      call b:ctx.write("println(\"NEXT_NEXT_NEXT\")\n")
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

fun! async_porcelaine#MakeOrGrep(cmd)
  let ctx = {'cmd': a:cmd , 'move_last':0, 'buf_name': '__GREP__MAKE__', 'line_prefix': ''}
  fun ctx.terminated()
    exec 'cbuffer '. self.bufnr
    bw! __GREP__MAKE__
  endf
  call async_porcelaine#LogToBuffer(ctx)
endf


" vim:fdm=marker
