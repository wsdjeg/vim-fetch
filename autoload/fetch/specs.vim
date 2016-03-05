" JUMP SPECS AUTOLOAD FUNCTION LIBRARY FOR VIM-FETCH
if &compatible || v:version < 700
  finish
endif

let s:cpoptions = &cpoptions
set cpoptions&vim

" Position specs Dictionary: {{{
" @type: SpecDictionary
" @desc: -'matcher' String pattern matching the spec in a file name
"        -'separator' String character signaling the start of a spec
"        -'pattern' String autocommand pattern for the spec
"        -'parse' Funcref taking a spec String and file path String
"          and returning a |call()| arguments List for the jump to execute
let s:specs = []

call add(s:specs, {
\        'name': 'colon',
\ 'description': "colon separated line and optional column spec, i.e. ':lnum[:colnum[:]]'",
\   'separator': ':',
\     'matcher': '\v%(:\d+){1,2}:?',
\     'pattern': '?*:[0123456789]*',
\ })
function! s:specs[-1].parse(specstr, file) abort
  let l:pos = split(matchstr(a:specstr, self.matcher), ':')
  return ['cursor', [l:pos[0], get(l:pos, 1, 0)]]
endfunction

call add(s:specs, {
\        'name': 'paren',
\ 'description': "parentheses enclosed line and optional column spec, i.e. '(lnum[:colnum])'",
\   'separator': '(',
\     'matcher': '\v\((\d+%(:\d+)?)\)',
\     'pattern': '?*([0123456789]*)',
\ })
function! s:specs[-1].parse(specstr, file) abort
  let l:pos = split(matchlist(a:specstr, self.matcher)[1], ':')
  return ['cursor', [l:pos[0], get(l:pos, 1, 0)]]
endfunction

call add(s:specs, {
\        'name': 'plan9',
\ 'description': "Plan 9 style line spec, i.e. '[:]#lnum'",
\   'separator': '#',
\     'matcher': '\v:?#(\d+)',
\     'pattern': '?*#[0123456789]*',
\ })
function! s:specs[-1].parse(specstr, file) abort
  let l:pos  = matchlist(a:specstr, self.matcher)[1]
  return ['cursor', [l:pos, 0]]
endfunction

call add(s:specs, {
\        'name': 'pytest',
\ 'description': "Pytest style method spec, i.e. '::method'",
\   'separator': ':',
\     'matcher': '\v::(\w+)',
\     'pattern': '?*::?*',
\ })
function! s:specs[-1].parse(specstr, file) abort
  let l:name   = matchlist(a:specstr, self.matcher)[1]
  let l:method = '\m\C^\s*def\s\+\%(\\\n\s*\)*\zs'.l:name.'\s*('
  return ['search', [l:method, 'cw']]
endfunction " }}}

" Get a copy of vim-fetch's spec matchers:
" @signature:  fetch#specs#list()
" @returns:    List<SpecDictionary>
function! fetch#specs#list() abort " {{{
  return deepcopy(s:specs)
endfunction " }}}

" Return a Dictionary of Lists of vimfetch's specs indexed by {key}:
" @signature:  fetch#specs#bykey({key:String})
" @returns:    Dictionary<List<SpecDictionary>>
function! fetch#specs#bykey(key) abort " {{{
  let l:specdict = {}
  for l:spec in fetch#specs#list()
    if has_key(l:spec, a:key)
      let l:specdict[l:spec[a:key]] = add(get(l:specdict, l:spec[a:key], []), l:spec)
    endif
  endfor
  return l:specdict
endfunction " }}}

" @type: SpecMatchDictionary
" @desc: -'pos' Number index of the match (-1 if no match)
"        -'spec' SpecDictionary of the matching spec (empty if no match)
"        -'match' String of the match (empty if no match)

" Check if a spec in {specs} matches in {string} (optionally from {start}):
" @signature:  fetch#specs#match({string:String}, {specs:List<SpecDictionary>}[, {start:Number}])
" @returns:    SpecMatchDictionary
" @notes:      pass a {start} of -1  to anchor the match at {string}'s end
function! fetch#specs#match(string, specs, ...) abort " {{{
  let l:matched  = {'pos': -1, 'spec': {}, 'match': ''}
  let l:matchpos = get(a:, 1, 0)
  for l:spec in a:specs
    let l:matcher = l:spec.matcher.(l:matchpos is -1 ? '\m$' : '')
    let l:matchat = match(a:string, l:matcher, l:matchpos)
    if  l:matchat isnot -1
      let l:matched.pos   = l:matchat
      let l:matched.spec  = l:spec
      let l:matched.match = matchstr(a:string, l:spec.matcher, l:matchat)
      break
    endif
  endfor
  return l:matched
endfunction " }}}

" Get all {specs} that match in {string} (optionally from {start}):
" @signature:  fetch#specs#matchlist({string:String}, {specs:List<SpecDictionary>}[, {start:Number}])
" @returns:    List<SpecMatchDictionary> (empty if no match)
" @notes:      pass a {start} of -1  to anchor the match at {string}'s end
function! fetch#specs#matchlist(string, specs, ...) abort " {{{
  let l:matched  = []
  let l:matchpos = get(a:, 1, 0)
  for l:spec in a:specs
    let l:specmatch = fetch#specs#match(a:string, l:spec, l:matchpos)
    if  l:specmatch.pos isnot -1
      call add(l:matched, l:specmatch)
    endif
  endfor
  return l:matched
endfunction " }}}

let &cpoptions = s:cpoptions
unlet! s:cpoptions

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
