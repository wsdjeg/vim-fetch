" SIMPLIFIED TAKE ON BOGADO/FILE-LINE (HOPEFULLY) WITHOUT THE WARTS
" Maintainer: Martin Kopischke <martin@kopischke.net>
" License:    MIT (see LICENSE.md)
" Version:    3.0.0
if &compatible || v:version < 700
  finish
endif

let s:cpoptions = &cpoptions
set cpoptions&vim

" Set up autocommands:
if has('autocmd')
  augroup fetch
    autocmd!
      " buffer operations started by buffer and window autocommands triggered
      " before Vim has fully loaded will choke off event processing after (or
      " sometimes even: inside) the first event processed. That was
      " `file_line`'s original problem (before switching it out for another set
      " of problems entirely by using `:argdo`). `BufWinEnter` was the exception
      " to this rule on older Vim versions, but at some point during Vim
      " 8 development, the init sequence subtly changed, closing that loophole.
      " The following autocommand juggling works both on Vim 7.4 and Vim 8.0:
      "
      " 1. check new files for a spec when Vim has finished its init sequence...
      autocmd BufNewFile *
      \ execute 'autocmd fetch VimEnter * nested call fetch#buffer("'.escape(expand('<afile>'), ' \\').'")'
      " 2. ... and start checking directly once the init sequence is complete
      autocmd VimEnter *
      \ execute 'autocmd! fetch BufNewFile * nested call fetch#buffer(expand("<afile>"))'

      " `fetch#buffer` is tab-local, so let's process buffers on other tab pages;
      " as of Vim 8.1522, I can't think of a way to create two or more windows
      " on a tab without activating that tab first, but let's go the extra mile
      " and make sure by cycling over all windows of the tab:
      if has('windows')
        autocmd TabEnter * nested for s:bufnr in tabpagebuflist() |
        \ call fetch#buffer(bufname(s:bufnr)) |
        \ unlet! s:bufnr |
        \ endfor
      endif
  augroup END
else
  " provide a manual alternative for Vim copies without '+autocmd'
  command Fetch -bar -nargs=0 call fetch#buffer(bufname('%'))
endif

" Set up mappings:
if has('file_in_path')
  nnoremap gF :<C-u>call fetch#cfile(v:count1)<CR>
  if has('visual')
    xnoremap gF :<C-u>call fetch#visual(v:count1)<CR>
  endif
endif

let &cpoptions = s:cpoptions
unlet! s:cpoptions

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
