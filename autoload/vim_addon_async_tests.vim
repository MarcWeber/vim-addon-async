fun! vim_addon_async_tests#TestLineBuffering()
  " tests that only full lines are passed to receive.
  let ctx = {'cmd': 'for l in `seq 3`; do for j in `seq 2`; do echo -n $j; sleep 1; done; echo; done; echo "done - You should have seen \"got 12\" 3 times"' }
  fun! ctx.receive(data, ...)
    call append('$', "got ".a:data)
  endf
  call async_porcelaine#LineBuffering(ctx)
  call async#Exec(ctx)
endf

fun! vim_addon_async_tests#Binary()
  echoe "you should see another error message telling that there were 0 failures"
  let s = ''
  for i in range(1,255)
    let s .= nr2char(i).nr2char(i)
  endfor
  let ctx =  {'zero_aware':1, 'cmd':'cat'}
  let ctx.data = s
  let ctx.pending = [""]
  let ctx.aslines = 1

  let g:binary_test_ctx = ctx

  let ctx.nr = 0
  let ctx.failures = 0

  fun ctx.receive_debug(data) abort
    if type(a:data) != type([])
      call feedkeys(":echoe 'wrong type'\<cr>")
    endif
    if a:data[0] != ''
      call feedkeys(":echoe 'wrong thing'\<cr>")
    endif
    let data = a:data[1]
    for i in range(0,len(data)-1)
      let got = data[i]
      let expected = self.data[self.nr]
      if got != expected
        let self.failures += 1
        call feedkeys(":echoe 'error with nr " . i ." got ".  char2nr(got) ." expected ". char2nr(expected) ."'\<cr>")
      endif
      let self.nr += 1

      if self.nr >= len(self.data)
        call feedkeys(":echoe 'end. you should have seen no additional errors. errors: ". self.failures ." '\<cr>")
        call self.kill()
      endif
    endfor
  endf

  fun ctx.receive(data, ...)
    call self.receive_debug(a:data)
  endf

  call async#Exec(ctx)
  call ctx.write(['', ctx.data])

endf

fun! vim_addon_async_tests#Chunksize(max)

  let ctx =  {'cmd':'seq '.a:max}
  let ctx.max = a:max
  let ctx.pending = ''

  fun ctx.receive(data, ...)
    let self.pending .= a:data

    let ok = split(self.pending,'[ \n]') == map(range(1,self.max),'v:val.""')
    if ok
      call feedkeys(":echoe 'success'\<cr>")
      call self.kill()
    endif
  endf

  call async#Exec(ctx)

  return ctx

endf
