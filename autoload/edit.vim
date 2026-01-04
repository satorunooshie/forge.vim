vim9script

if exists('g:loaded_forge_edit')
  finish
endif

g:loaded_forge_edit = 1

def MakeId(name: string): string
  return sha256(name .. '-' .. localtime() .. '-' .. reltimestr(reltime()))[0 : 7]
enddef

def NormalizeName(name: string): string
  return substitute(name, '[/\\]$', '', '')
enddef

var idname: string = 'forge-edit'

def PropAddLineId(lnum: number, file: string): dict<any>
  # Skip adding an ID for empty lines so that
  # they are treated as new entries (create)
  # rather than renames of a non-existent path.
  if file ==# ''
    if len(prop_list(lnum, {'type': idname})) > 0
      prop_clear(lnum)
    endif
    return {'id': '', 'name': ''}
  endif

  if len(prop_list(lnum, {'type': idname})) > 0
    prop_clear(lnum)
  endif
  var id = MakeId(file)
  var prop_id = prop_add(lnum, 0, {'type': idname, 'text': id, 'text_align': 'right'})
  var prop = {'id': id, 'name': file}
  if !exists('b:forge_idmap')
    b:forge_idmap = {}
  endif
  b:forge_idmap[prop_id] = prop
  return prop
enddef

def GetLineTextprop(lnum: number): dict<any>
  var plist = prop_list(lnum, {'type': idname})
  if empty(plist)
    return {'id': '', 'name': ''}
  endif
  var prop = plist[0]
  if has_key(prop, 'id') && has_key(b:forge_idmap, prop['id'])
    return b:forge_idmap[prop['id']]
  endif
  var text = get(prop, 'text', '')
  for [_, v] in items(b:forge_idmap)
    if v['id'] ==# text
      return v
    endif
  endfor
  return {'id': '', 'name': ''}
enddef

def ForgeEditStart(): void
  if !exists('b:forge_idmap')
    b:forge_idmap = {}
  endif

  var dir = forge#Curdir()
  var files = getline(1, '$')

  setlocal modifiable buftype=acwrite noreadonly

  if empty(prop_type_get(idname))
    prop_type_add(idname, { 'highlight': 'NonText' })
  endif

  for lnum in range(1, line('$'))
    prop_clear(lnum)
  endfor

  for idx in range(len(files))
    PropAddLineId(idx + 1, files[idx])
  endfor

  augroup _forge_edit_
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> call Apply()
  augroup END
enddef

def Apply(): void
  var dir = forge#Curdir()
  var operations: list<dict<any>> = []

  var lines = getline(1, '$')
  filter(lines, (_, v: string) => v !~ '^\s*$')

  for idx in range(len(lines))
    var line = lines[idx]
    var basename = substitute(line, '[/\\]$', '', '')

    if basename ==# '..' || basename ==# '.' || basename ==# ''
      echohl ErrorMsg
      echom 'Error: Invalid filename "' .. line .. '"' .. ' on line ' .. (idx + 1) .. ' (cannot be . or .. or empty)'
      echohl None
      return
    endif

    if basename =~# '\v^\.\.?[/\\]'
      echohl ErrorMsg
      echom 'Error: Invalid filename "' .. line .. '"' .. ' on line ' .. (idx + 1) .. ' (cannot start with ./ or ../)'
      echohl None
      return
    endif
  endfor

  var willBeDeleted: list<dict<any>> = []
  var processedIds: list<string> = []

  for idx in range(len(lines))
    var line = lines[idx]

    var prop = GetLineTextprop(idx + 1)
    if prop ==# {'id': '', 'name': ''}
      if filereadable(dir .. '/' .. line)
        echohl ErrorMsg
        echom 'Error: Duplicate filename "' .. line .. '" on line ' .. (idx + 1)
        echohl None
        continue
      endif
      if isdirectory(dir .. '/' .. line)
        echohl ErrorMsg
        echom 'Error: Duplicate directory name "' .. line .. '" on line ' .. (idx + 1)
        echohl None
        continue
      endif
    endif

    var oldname = prop['name']

    if prop['id'] ==# ''
      if line =~# '[/\\]$'
        add(operations, {'op': 'create_dir', 'name': line, 'lnum': idx + 1})
      else
        add(operations, {'op': 'create', 'name': line, 'lnum': idx + 1})
      endif
      continue
    endif

    var oldNorm = NormalizeName(oldname)
    var newNorm = NormalizeName(line)

    if oldNorm !=# newNorm
      if line =~# '[/\\].'
        # Move (path changed and now contains a directory component)
        if filereadable(dir .. '/' .. oldname) || isdirectory(dir .. '/' .. oldname)
          add(operations, {'op': 'move', 'oldname': oldname, 'newname': line, 'lnum': idx + 1})
          add(processedIds, prop['id'])
        endif
      else
        # Simple rename within the same directory
        if filereadable(dir .. '/' .. oldname) || isdirectory(dir .. '/' .. oldname)
          add(operations, {'op': 'rename', 'oldname': oldname, 'newname': line, 'lnum': idx + 1})
          add(processedIds, prop['id'])
        endif
      endif
    endif
  endfor

  # Deletions entries that existed before (in b:forge_idmap),
  # are not present in current lines, and were not moved/renamed.
  for [_, mapEntry] in items(b:forge_idmap)
    var mappedName = mapEntry['name']
    if index(lines, mappedName) == -1 && index(processedIds, mapEntry['id']) == -1
      add(willBeDeleted, mapEntry)
    endif
  endfor

  for deleteEntry in willBeDeleted
    var deleteName = deleteEntry['name']
    if filereadable(dir .. '/' .. deleteName)
      add(operations, {'op': 'delete', 'name': deleteName, 'lnum': 0})
    elseif isdirectory(dir .. '/' .. deleteName)
      add(operations, {'op': 'delete_dir', 'name': deleteName, 'lnum': 0})
    endif
  endfor

  if empty(operations)
    setlocal nomodified
    echohl WarningMsg
    echomsg 'No changes to apply.'
    echohl None
    return
  endif

  var qflist: list<dict<any>> = []
  # seenOps is only used to deduplicate identical operations in the quickfix list
  # so that the UI does not show multiple entries for the same logical change.
  var seenOps: dict<any> = {}

  for [i, op] in items(operations)
    var key = op['op']
    if has_key(op, 'name')
      key ..= ':' .. op['name']
    endif
    if has_key(op, 'oldname')
      key ..= ':' .. op['oldname']
    endif
    if has_key(op, 'newname')
      key ..= ':' .. op['newname']
    endif
    if has_key(seenOps, key)
      continue
    endif
    seenOps[key] = 1

    var lnum = get(op, 'lnum', 0)
    var filename = ''
    if op['op'] ==# 'create' || op['op'] ==# 'create_dir'
      filename = dir .. '/' .. op['name']
    elseif op['op'] ==# 'move' || op['op'] ==# 'rename'
      filename = dir .. '/' .. op['newname']
    elseif op['op'] ==# 'delete' || op['op'] ==# 'delete_dir'
      filename = dir .. '/' .. op['name']
    endif

    if op['op'] ==# 'create'
      # Create parent directories if needed when using a nested path
      var fullpath = dir .. '/' .. op['name']
      var parent = fnamemodify(fullpath, ':h')
      if parent !=# '' && !isdirectory(parent)
        mkdir(parent, 'p')
      endif
      writefile([], fullpath)
      if lnum > 0
        PropAddLineId(lnum, op['name'])
      endif
      add(qflist, {'text': '[+] created: ' .. op['name'], 'nr': i + 1, 'lnum': lnum, 'filename': filename, 'type': 'I'})
    elseif op['op'] ==# 'create_dir'
      mkdir(dir .. '/' .. op['name'], 'p')
      if lnum > 0
        PropAddLineId(lnum, op['name'])
      endif
      add(qflist, {'text': '[+] created dir: ' .. op['name'], 'nr': i + 1, 'lnum': lnum, 'filename': filename, 'type': 'I'})
    elseif op['op'] ==# 'move'
      rename(dir .. '/' .. op['oldname'], dir .. '/' .. op['newname'])
      if lnum > 0
        PropAddLineId(lnum, op['newname'])
      endif
      add(qflist, {'text': '[>] moved: ' .. op['oldname'] .. ' to ' .. op['newname'], 'nr': i + 1, 'lnum': lnum, 'filename': filename, 'type': 'I'})
    elseif op['op'] ==# 'rename'
      rename(dir .. '/' .. op['oldname'], dir .. '/' .. op['newname'])
      if lnum > 0
        PropAddLineId(lnum, op['newname'])
      endif
      add(qflist, {'text': '[~] renamed: ' .. op['oldname'] .. ' to ' .. op['newname'], 'nr': i + 1, 'lnum': lnum, 'filename': filename, 'type': 'I'})
    elseif op['op'] ==# 'delete'
      delete(dir .. '/' .. op['name'])
      add(qflist, {'text': '[-] deleted: ' .. op['name'], 'nr': i + 1, 'lnum': lnum, 'filename': filename, 'type': 'I'})
    elseif op['op'] ==# 'delete_dir'
      delete(dir .. '/' .. op['name'], 'rf')
      add(qflist, {'text': '[-] deleted dir: ' .. op['name'], 'nr': i + 1, 'lnum': lnum, 'filename': filename, 'type': 'I'})
    endif
  endfor

  # When creating nested paths like "hoge/fuga/" or "hoge/fuga.txt"
  # from a parent directory, make sure the top-level parent ("hoge/")
  # is visible as an entry in the current forge buffer. Otherwise it
  # can look like nothing changed because the nested path line is
  # removed below.
  var parents: list<string> = []
  for op in operations
    if (op['op'] ==# 'create' || op['op'] ==# 'create_dir') && has_key(op, 'name')
      var name = op['name']
      # Strip a trailing separator so we can reliably
      # extract the top-level parent directory name.
      var nameNoTrail = substitute(name, '[/\\]$', '', '')
      if nameNoTrail =~# '[/\\]'
        var sepidx = match(nameNoTrail, '[/\\]')
        if sepidx > 0
          var parent = nameNoTrail[0 : sepidx - 1] .. '/'
          if index(parents, parent) == -1
            add(parents, parent)
          endif
        endif
      endif
    endif
  endfor

  if !empty(parents)
    var bufLines = getline(1, '$')
    for parent in parents
      if index(bufLines, parent) == -1
        append(line('$'), parent)
        PropAddLineId(line('$'), parent)
        add(bufLines, parent)
      endif
    endfor
  endif

  try
    noautocmd noswapfile keepalt silent :%g/[/\\]./d _
  catch
    # Ignore errors (e.g. E486 pattern not found).
  endtry

  setlocal nomodified

  if !empty(qflist)
    setqflist(qflist)
    setqflist([], 'r', {'title': 'Forge Operations'})
    silent copen 8 | wincmd p
  else
    silent cclose
  endif

  redraw
  echohl ModeMsg
  echomsg 'Applied ' .. len(operations) .. ' operations.'
  echohl None
enddef

export def ForgeEdit(): void
  if &filetype !=# 'forge'
    echohl ErrorMsg
    echomsg 'ForgeEdit can only be used in forge buffers.'
    echohl None
    return
  endif
  ForgeEditStart()
enddef
