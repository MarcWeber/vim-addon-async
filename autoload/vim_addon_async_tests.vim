fun! vim_addon_async_tests#TestLineBuffering()
  " tests that only full lines are passed to receive.
  let ctx = {'cmd': 'for l in `seq 3`; do for j in `seq 2`; do echo -n $j; sleep 1; done; echo; done; echo "done - You should have seen \"got 12\" 3 times' }
  fun! ctx.receive(data, ...)
    call append('$', "got ".a:data)
  endf
  call async_porcelaine#LineBuffering(ctx)
  call async#Exec(ctx)
endf

fun! vim_addon_async_tests#Binary()
  let s = ''
  for i in range(1,255)
    let s .= nr2char(i)
  endfor
  let ctx =  {'zero_aware':1, 'cmd':'cat'}
  let ctx.data = ['',s]
  let ctx.pending = [""]

  fun ctx.receive(data, ...)
    let self.pending[-1] = self.pending[-1].a:data[0]
    let self.pending += a:data[1:]

    let ok = self.data == self.pending
    if ok
      debug call feedkeys(":echoe 'success'\<cr>")
    endif
    call self.kill()
  endf

  call async#Exec(ctx)
  call ctx.write(ctx.data)

endf
