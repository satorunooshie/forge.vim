vim9script

import autoload 'edit.vim' as forge_edit

export def Init(): void
  var path: string = resolve(expand('%:p'))
  if !isdirectory(path)
    return
  endif

  var dir: string = fnamemodify(path, ':p:gs!\!/!')
  if isdirectory(dir) && dir !~# '/$'
    dir ..= '/'
  endif

  b:forge_dir = dir
  noautocmd noswapfile keepalt silent file `=b:forge_dir`
  setlocal modifiable
  setlocal buftype=nofile filetype=forge bufhidden=unload nobuflisted noswapfile
  setlocal nowrap cursorline

  var files: list<string>
  if exists('*readdirex')
    var entries = readdirex(path, '1', {'sort': 'none'})
    files = []
    for entry in entries
      add(files, Name(dir, entry))
    endfor
  else
    var names = readdir(path, '1')
    files = []
    for name in names
      add(files, Name(dir, {'type': getftype(dir .. '/' .. name), 'name': name}))
    endfor
  endif

  if !get(b:, 'forge_show_hidden', get(g:, 'forge_show_hidden', 0))
    files = filter(files, (_, v) => v =~# '^[^.]')
  endif

  silent keepmarks keepjumps call setline(1, sort(files, Sort))
  setlocal nomodified nomodifiable

  # Automatically enable edit extension for forge buffers by default.
  # Users can disable this with: let g:forge_enable_edit = 0
  # ForgeEdit() itself checks &filetype ==# 'forge'.
  if get(g:, 'forge_enable_edit', 1)
    forge_edit.ForgeEdit()
  endif

  var alt = fnamemodify(expand('#'), ':p:h:gs!\!/!')
  if substitute(dir, '/$', '', '') ==# alt
    alt = fnamemodify(expand('#'), ':t')
    search('\v^\V' .. escape(alt, '\') .. '\v$', 'c')
  endif
enddef

def Sort(lhs: string, rhs: string): number
  if lhs[-1 : ] ==# '/' && rhs[-1 : ] !=# '/'
    return -1
  elseif lhs[-1 : ] !=# '/' && rhs[-1 : ] ==# '/'
    return 1
  endif
  if lhs < rhs
    return -1
  elseif lhs > rhs
    return 1
  endif
  return 0
enddef

def Name(base: string, v: dict<any>): string
  var type = v['type']
  if type ==# 'link' || type ==# 'junction'
    if isdirectory(resolve(base .. v['name']))
      type = 'dir'
    endif
  elseif type ==# 'linkd'
    type = 'dir'
  endif
  return v['name'] .. (type ==# 'dir' ? '/' : '')
enddef

export def Chdir(): void
  if get(b:, 'forge_dir', '') ==# ''
    return
  endif
  noautocmd silent file `=getcwd()`
  Init()
enddef

export def Startup(): void
  if &filetype ==# 'forge'
    return
  endif

  if argc() == 1
    var a0 = resolve(fnamemodify(argv(0), ':p'))
    if isdirectory(a0)
      var dir = substitute(a0, '/$', '', '')
      execute 'silent keepalt noautocmd edit' fnameescape(dir)
      Init()
    endif
  endif
enddef

export def Open(): void
  var split = getline('.') =~# '/$' ? 'edit' : get(g:, 'forge_open_split', 'edit')
  execute split fnameescape(b:forge_dir .. substitute(getline('.'), '/$', '', ''))
enddef

export def Up(): void
  # Go up exactly one directory from the current forge directory.
  var cur = forge#Curdir()
  if empty(cur)
    return
  endif

  # Strip trailing slash and compute parent.
  var child = substitute(cur, '/$', '', '')
  var parent = fnamemodify(child, ':h')

  # If we are already at the filesystem root, do nothing.
  if parent ==# child
    return
  endif

  var name = fnamemodify(child, ':t:gs!\!/!')
  execute 'edit' fnameescape(parent)
  search('\v^\V' .. escape(name, '\') .. '/\v$', 'c')
enddef

export def Home(): void
  execute 'edit' fnameescape(substitute(fnamemodify(expand('~'), ':p:gs!\!/!'), '/$', '', ''))
enddef

export def Reload(): void
  edit
enddef

export def Curdir(): any
  return get(b:, 'forge_dir', '')
enddef

def Current(): any
  return getline('.')
enddef

export def ToggleHidden(): void
  b:forge_show_hidden = !get(b:, 'forge_show_hidden', get(g:, 'forge_show_hidden', 0))
  Reload()
enddef
