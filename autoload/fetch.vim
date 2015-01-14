" AUTOLOAD FUNCTION LIBRARY FOR VIM-FETCH

" Position specs Dictionary:
let s:specs = {}

" - trailing colon, i.e. ':lnum[:colnum[:]]'
"   trigger with '*:*' pattern
let s:specs.colon = {'pattern': '\m\%(:\d\+\)\{1,2}:\?$'}
function! s:specs.colon.parse(file) abort
  return [substitute(a:file, self.pattern, '', ''),
        \ split(matchstr(a:file, self.pattern), ':')]
endfunction

" - trailing parentheses, i.e. '(lnum[:colnum])'
"   trigger with '*(*)' pattern
let s:specs.paren = {'pattern': '\m\(\(\d\+\%(:\d\+\)\?\))$'}
function! s:specs.paren.parse(file) abort
  return [substitute(a:file, self.pattern, '', ''),
        \ split(matchlist(a:file, self.pattern)[1], ':')]
endfunction

" Edit {file}, placing the cursor at the line and column indicated by {spec}:
" @signature:  fetch#edit({file:String}, {spec:String})
" @notes:      won't work from a |BufReadCmd| event as it does not load non-spec files
function! fetch#edit(file, spec) abort
  let l:spec = get(s:specs, a:spec, {})

  " get spec data if needed, else bail
  if empty(l:spec) || filereadable(a:file) || match(a:file, l:spec.pattern) is -1
    return
  endif
  let [l:file, l:pos] = l:spec.parse(a:file)
  let l:cmd = ''

  " get rid of the spec'ed buffer
  if expand('%:p') is fnamemodify(a:file, ':p')
    set bufhidden=wipe      " avoid issues with |bwipeout|
    let l:cmd .= 'keepalt ' " don't mess up alternate file on switch
  endif

  " clean up argument list
  if has('listcmds')
    let l:argidx = index(argv(), a:file)
    if  l:argidx isnot -1   " substitute un-spec'ed file for spec'ed
      execute 'argdelete' a:file
      execute l:argidx.'argadd' l:file
    endif
    if index(argv(), l:file) isnot -1
      let l:cmd .= 'arg'    " set arglist index to edited file
    endif
  endif

  " open correct file and place cursor at position spec
  execute l:cmd.'edit!' fnameescape(l:file)
  call cursor(max([l:pos[0], 1]), max([get(l:pos, 1, 0), 1]))
  silent! normal! zO
endfunction

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
