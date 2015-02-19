" VIM-STAY INTEGRATION MODULE
" https://github.com/kopischke/vim-stay
let s:cpoptions = &cpoptions
set cpoptions&vim

" - register integration autocommands
function! stay#integrate#fetch#setup() abort
  autocmd User BufFetchPosPost let b:stay_atpos = b:fetch_lastpos
endfunction

let &cpoptions = s:cpoptions
unlet! s:cpoptions

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
