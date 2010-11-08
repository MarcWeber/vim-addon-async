fun! vim_addon_async_tests#TestLineBuffering()
  " tests that only full lines are passed to receive.
  let ctx = {'cmd': 'for l in `seq 3`; do for j in `seq 2`; do echo -n $j; sleep 1; done; echo; done; echo "done - You should have seen \"got 12\" 3 times' }
  fun! ctx.receive(data, ...)
    call append('$', "got ".a:data)
  endf
  call async_porcelaine#LineBuffering(ctx)
  call async#Exec(ctx)
endf
