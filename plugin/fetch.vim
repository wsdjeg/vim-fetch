" SIMPLIFIED TAKE ON BOGADO/FILE-LINE (HOPEFULLY) WITHOUT THE WARTS
" Maintainer: Martin Kopischke <martin@kopischke.net>
" License:    MIT (see LICENSE.md)
" Version:    1.3.0
if &compatible || !has('autocmd') || v:version < 700
  finish
endif

let s:cpo = &cpo
set cpo&vim

" Based on |BufNewFile|, but flanked by |BufWinEnter| to correctly process all
" buffers in an |arglist| passed with '-o/-O' resp. '-p' (see
" |windows-starting| for some background, though that omits to mention that
" |BufRead| events are also skipped, as is |BufNewFile|, that |BufWinEnter|
" events *are* fired for all buffers, and relies on implicitly understanding
" that the first buffer of the list is activated after loading all files, but
" that the usual event sequence still is out of kilter; also note there is no
" equivalent help section for '-p' though its behaviour is analogous).
"
" Note the use of highly spec specific file name patterns to avoid autocommand
" flooding when nesting (which is needed as we switch buffers out).
let s:matchers = {
  \   'colon': '?*:[0123456789]*',
  \   'paren': '?*([0123456789]*)',
  \   'plan9': '?*#[0123456789]*',
  \ }

augroup fetch
  autocmd!
  for [s:spec, s:pat] in items(s:matchers)
    execute 'autocmd BufNewFile,BufWinEnter' s:pat
          \ 'nested call fetch#edit(expand("<afile>"), "'.s:spec.'")'
    unlet! s:spec s:pat
  endfor
augroup END

let &cpo = s:cpo
unlet! s:cpo

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
