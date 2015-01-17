" SIMPLIFIED TAKE ON BOGADO/FILE-LINE (HOPEFULLY) WITHOUT THE WARTS
" Maintainer: Martin Kopischke <martin@kopischke.net>
" License:    MIT (see LICENSE.md)
" Version:    1.1.0
if &compatible || !has('autocmd')
  finish
endif

" Based on |BufWinEnter| to correctly process all buffers in the initial
" |arglist| (see |windows-starting| for some background, though that omits to
" mention that |BufRead| events are also skipped, as is |BufNewFile|, that
" |BufWinEnter| events *are* fired for all buffers, and relies on implicit
" understanding that the first buffer of the list is activated after loading,
" thus triggering all relevant events; also note there is no equivalent help
" section for '-p' though its behaviour is analogous).
"
" The extra |WinEnter| and |TabEnter| events are needed to correctly process
" the first file in an |arglist| passed with '-o/-O' resp. '-p'; without them,
" the first buffer is correctly loaded, but its window still displays the
" spec'ed version of the file  (go figure; no, I'm not sure I want to know).
"
" Note the use of spec specific file name patterns to avoid autocommand
" flooding when nesting.
let s:matchers = {
  \   'colon': '*:[0123456789]*',
  \   'paren': '*([0123456789]*)',
  \   'plan9': '*#[0123456789]*',
  \ }
let s:events   = has('windows') ? 'BufWinEnter,WinEnter,TabEnter' : 'BufWinEnter,WinEnter'
augroup fetch
  autocmd!
  for [s:spec, s:pat] in items(s:matchers)
    execute 'autocmd' s:events s:pat 'nested call fetch#edit(expand("<afile>"), "'.s:spec.'")'
    unlet! s:spec s:pat
  endfor
augroup END

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
