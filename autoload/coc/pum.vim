scriptencoding utf-8
let s:is_vim = !has('nvim')
let s:float = has('nvim-0.4.0') || has('patch-8.1.1719')
let s:pum_bufnr = 0
let s:pum_winid = 0
let s:inserted = 0

function! coc#pum#visible() abort
  if !s:float || !s:pum_winid
    return 0
  endif
  return getwinvar(s:pum_winid, 'float', 0) == 1
endfunction

function! coc#pum#winid() abort
  return s:pum_winid
endfunction

function! coc#pum#close_detail() abort
  let winid = coc#float#get_float_by_kind('pumdetail')
  if winid
    call coc#float#close(winid)
    if s:is_vim
      call timer_start(0, { -> execute('redraw')})
    endif
  endif
endfunction

function! coc#pum#close(...) abort
  if coc#float#valid(s:pum_winid)
    if get(a:, 1, '') ==# 'cancel'
      let input = getwinvar(s:pum_winid, 'input', '')
      call s:insert_word(input)
      doautocmd TextChangedI
    elseif get(a:, 1, '') ==# 'confirm'
      let words = getwinvar(s:pum_winid, 'words', [])
      let index = coc#window#get_cursor(s:pum_winid)[0] - 1
      let word = get(words, index, '')
      call s:insert_word(word)
      doautocmd TextChangedI
    endif
    call coc#float#close(s:pum_winid)
    let s:pum_winid = 0
    let winid = coc#float#get_float_by_kind('pumdetail')
    if winid
      call coc#float#close(winid)
    endif
    if !get(a:, 2, 0)
      call coc#rpc#notify('CompleteStop', [get(a:, 1, '')])
    endif
  endif
endfunction

function! coc#pum#next(insert) abort
  call timer_start(10, { -> s:navigate(1, a:insert)})
  return ''
endfunction

function! coc#pum#prev(insert) abort
  call timer_start(10, { -> s:navigate(0, a:insert)})
  return ''
endfunction

function! coc#pum#stop() abort
  call timer_start(10, { -> coc#pum#close()})
  return "\<Ignore>"
endfunction

function! coc#pum#cancel() abort
  call timer_start(10, { -> coc#pum#close('cancel')})
  return ''
endfunction

function! coc#pum#confirm() abort
  call timer_start(10, { -> coc#pum#close('confirm')})
  return ''
endfunction

function! coc#pum#select(index, insert, confirm) abort
  if !coc#float#valid(s:pum_winid)
    return ''
  endif
  if a:index == -1
    call coc#pum#close('cancel')
    return ''
  endif
  let total = coc#compat#buf_line_count(s:pum_bufnr)
  if a:index < 0 || a:index >= total
    throw 'index out of range ' . a:index
  endif
  call s:select_by_index(a:index, a:insert)
  if a:confirm
    call coc#pum#close('confirm')
  endif
  return ''
endfunction

function! coc#pum#info() abort
  let bufnr = winbufnr(s:pum_winid)
  let size = coc#compat#buf_line_count(bufnr)
  let index = coc#window#get_cursor(s:pum_winid)[0] - 1
  if s:is_vim
    let pos = popup_getpos(s:pum_winid)
    let add = pos['scrollbar'] && has_key(popup_getoptions(s:pum_winid), 'border') ? 1 : 0
    return {
        \ 'index': index,
        \ 'scrollbar': pos['scrollbar'],
        \ 'row': pos['line'] - 1,
        \ 'col': pos['col'] - 1,
        \ 'width': pos['width'] + add,
        \ 'height': pos['height'],
        \ 'size': size,
        \ 'inserted': s:inserted ? v:true : v:false,
        \ }
  else
    let scrollbar = coc#float#get_related(s:pum_winid, 'scrollbar')
    let winid = coc#float#get_related(s:pum_winid, 'border', s:pum_winid)
    let pos = nvim_win_get_position(winid)
    return {
        \ 'index': index,
        \ 'scrollbar': scrollbar && nvim_win_is_valid(scrollbar) ? 1 : 0,
        \ 'row': pos[0],
        \ 'col': pos[1],
        \ 'width': nvim_win_get_width(winid),
        \ 'height': nvim_win_get_height(winid),
        \ 'size': size,
        \ 'inserted': s:inserted ? v:true : v:false,
        \ }
  endif
endfunction

function! s:navigate(next, insert) abort
  if !coc#float#valid(s:pum_winid)
    return
  endif
  let index = s:get_index(a:next)
  call s:select_by_index(index, a:insert)
endfunction

function! s:select_by_index(index, insert) abort
  call s:set_cursor(s:pum_winid, a:index + 1)
  if !s:is_vim
    call coc#float#nvim_scrollbar(s:pum_winid)
  endif
  if a:insert
    let s:inserted = 1
    let words = getwinvar(s:pum_winid, 'words', [])
    let word = get(words, a:index, '')
    call s:insert_word(word)
    doautocmd TextChangedP
  endif
  call s:on_pum_change(1)
endfunction

function! s:get_index(next) abort
  let result = s:get_index_size()
  let [index, size] = result
  if a:next
    let index = index + 1 == size ? 0 : index + 1
  else
    let index = index == 0 ? size - 1 : index - 1
  endif
  return index
endfunction

function! s:insert_word(word) abort
  let parts = getwinvar(s:pum_winid, 'parts', [])
  if !empty(parts)
    let curr = getline('.')
    if curr ==# parts[0].a:word.parts[1]
      return
    endif
    if !exists('*nvim_buf_set_text')
      noa call setline('.', parts[0].a:word.parts[1])
      noa call cursor(line('.'), strlen(parts[0].a:word) + 1)
    else
      let row = line('.') - 1
      let startCol = strlen(parts[0])
      let endCol = strlen(getline('.')) - strlen(parts[1])
      call nvim_buf_set_text(bufnr('%'), row, startCol, row, endCol, [a:word])
      call cursor(line('.'), strlen(parts[0].a:word) + 1)
    endif
  endif
endfunction

" create or update pum with lines, CompleteOption and config.
" return winid & dimension
function! coc#pum#create(lines, opt, config) abort
  if a:opt['bufnr'] != bufnr('%') || a:opt['line'] != line('.')
    return
  endif
  let len = col('.') - a:opt['col'] - 1
  if len < 0
    return
  endif
  let input = len == 0 ? '' : strpart(getline('.'), a:opt['col'], len)
  if input !=# a:opt['input']
    return
  endif
  let config = s:get_pum_dimension(a:lines, a:opt['col'], a:config)
  if empty(config)
    return
  endif
  let selected = a:opt['index'] + 1
  call extend(config, {
        \ 'lines': a:lines,
        \ 'relative': 'cursor',
        \ 'nopad': 1,
        \ 'cursorline': 1,
        \ 'index': a:opt['index'],
        \ 'focusable': v:false
        \ })
  call extend(config, coc#dict#pick(a:config, ['highlight', 'rounded', 'highlights', 'winblend', 'shadow', 'border', 'borderhighlight']))
  let result =  coc#float#create_float_win(s:pum_winid, s:pum_bufnr, config)
  if empty(result)
    return
  endif
  let s:inserted = 0
  let s:pum_winid = result[0]
  let s:pum_bufnr = result[1]
  let lnum = a:opt['index'] + 1
  if s:is_vim
    call popup_setoptions(s:pum_winid, {
          \ 'firstline': s:get_firstline(lnum, len(a:lines), config['height'])
          \ })
  else
    let firstline = s:get_firstline(lnum, len(a:lines), config['height'])
    call coc#compat#execute(s:pum_winid, 'call winrestview({"lnum":'.lnum.',"topline":'.firstline.'})')
  endif
  call coc#dialog#place_sign(s:pum_bufnr, config['index'] + 1)
  call setwinvar(s:pum_winid, 'kind', 'pum')
  " content before col and content after cursor
  let linetext = getline('.')
  let parts = [strpart(linetext, 0, a:opt['col']), strpart(linetext, col('.') - 1)]
  call setwinvar(s:pum_winid, 'input', input)
  call setwinvar(s:pum_winid, 'parts', parts)
  call setwinvar(s:pum_winid, 'words', a:opt['words'])
  if !s:is_vim
    if len(a:lines) > config['height']
      redraw
      call coc#float#nvim_scrollbar(s:pum_winid)
    else
      call coc#float#close_related(s:pum_winid, 'scrollbar')
    endif
  endif
  call timer_start(10, { -> s:on_pum_change(0)})
endfunction

function! s:get_firstline(lnum, total, height) abort
  if a:lnum <= a:height
    return 1
  endif
  return min([a:total - a:height + 1, a:lnum  - (a:height*2/3)])
endfunction

function! s:on_pum_change(move) abort
  if coc#float#valid(s:pum_winid)
    let ev = extend(coc#pum#info(), {'move': a:move ? v:true : v:false})
    call coc#rpc#notify('CocAutocmd', ['MenuPopupChanged', ev, win_screenpos(winnr())[0] + winline() - 2])
  endif
endfunction

function! s:get_pum_dimension(lines, col, config) abort
  let linecount = len(a:lines)
  let [lineIdx, colIdx] = coc#cursor#screen_pos()
  let bh = empty(get(a:config, 'border', [])) ? 0 : 2
  let width = min([&columns - colIdx - bh, max([&pumwidth, a:config['width']])])
  let showTop = 0
  let vh = &lines - &cmdheight - 1 - !empty(&tabline)
  if vh <= 0
    return v:null
  endif
  let pumheight = empty(&pumheight) ? vh : &pumheight
  if vh - lineIdx - bh - 1 < min([pumheight, linecount]) && lineIdx > vh - lineIdx
    let showTop = 1
  endif
  let height = showTop ? min([lineIdx - bh - !empty(&tabline), linecount, pumheight]) : min([vh - lineIdx - bh - 1, linecount, pumheight])
  if height <= 0
    return v:null
  endif
  let col = - (col('.') - a:col - 1) - 1
  let row = showTop ? - height : 1
  let delta = colIdx + col
  if delta < 0
    let col = col - delta
  endif
  return {
        \ 'row': row,
        \ 'col': col,
        \ 'width': width,
        \ 'height': height
        \ }
endfunction

function! s:get_index_size() abort
  let index = coc#window#get_cursor(s:pum_winid)[0] - 1
  return [index, coc#compat#buf_line_count(s:pum_bufnr)]
endfunction

" can't use coc#dialog#set_cursor on vim8, don't know why
function! s:set_cursor(winid, line) abort
  if s:is_vim
    let pos = popup_getpos(a:winid)
    let lastline = pos['firstline'] + pos['core_height'] - 1
    if a:line > lastline
      call popup_setoptions(a:winid, {
            \ 'firstline': pos['firstline'] + a:line - lastline,
            \ })
    elseif a:line < pos['firstline']
      call popup_setoptions(a:winid, {
            \ 'firstline': a:line,
            \ })
    endif
    call coc#compat#execute(a:winid, 'exe '.a:line)
  else
    call nvim_win_set_cursor(a:winid, [a:line, 0])
  endif
  call coc#dialog#place_sign(winbufnr(a:winid), a:line)
endfunction
