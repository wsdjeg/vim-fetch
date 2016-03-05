" SIMPLIFIED TAKE ON BOGADO/FILE-LINE (HOPEFULLY) WITHOUT THE WARTS
" Maintainer: Martin Kopischke <martin@kopischke.net>
" License:    MIT (see LICENSE.md)
" Version:    2.0.2
if &compatible || !has('autocmd') || v:version < 700
  finish
endif

let s:cpoptions = &cpoptions
set cpoptions&vim

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
let s:specdict = fetch#specs#bykey('pattern')
let s:speclist = fetch#specs#list()

" Set up autocommands:
augroup fetch
  autocmd!
  for s:pattern in keys(s:specdict)
    execute 'autocmd BufNewFile,BufWinEnter' s:pattern
          \ 'nested call fetch#buffer(s:specdict["'.s:pattern.'"])'
    unlet! s:pattern
  endfor
augroup END

" Set up mappings:
nnoremap gF :<C-u>call fetch#cfile(v:count1, <SID>speclist)<CR>
xnoremap gF :<C-u>call fetch#visual(v:count1, <SID>speclist)<CR>

let &cpoptions = s:cpoptions
unlet! s:cpoptions

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
