# forge.vim

Vim9-only directory browser with an inline “edit mode” for creating, renaming,
moving, and deleting files and directories by editing a buffer.

This implementation is heavily inspired by:

- https://github.com/mattn/vim-molder
- https://github.com/mattn/vim-molder-oil

## Requirements

- Vim 9.0+ (Vim9 script, text properties, ideally `readdirex()`)
- Neovim is not supported.

## Basic usage

Open a directory with Vim:

```sh
vim path/to/dir
```

`forge#Init()` turns the buffer into a *forge buffer*:

- `buftype=nofile`, `filetype=forge`
- One entry per line (`name/` for dirs, `name` for files)
- Hidden files can be toggled.

Navigation (see `plugin/forge.vim`):

- `<Plug>(forge-open)` – open under cursor
- `<Plug>(forge-up)` – go up one directory
- `<Plug>(forge-reload)` – reload listing
- `<Plug>(forge-home)` – jump to `$HOME`
- `<Plug>(forge-toggle-hidden)` – toggle hidden entries

Example mappings:

```vim
nnoremap - <Plug>(forge-open)
nnoremap _ <Plug>(forge-up)
```

## Edit mode

Edit mode is implemented in `autoload/edit.vim`. In a forge buffer:

- **New line** → create file/dir (`foo.txt`, `bar/`, `sub/dir/file.txt`)
- **Change line** → rename or move
- **Delete line** → delete file/dir

When edit mode is enabled:

- Buffer becomes `modifiable` with `buftype=acwrite`
- Each line gets an internal ID via text properties
- `:write` applies operations instead of writing the buffer
- Results are shown in the quickfix window.

## Enabling edit mode

Edit mode has two entry points:

1. **Automatic on init** (default)

   In `autoload/forge.vim`:

   ```vim
   if get(g:, 'forge_enable_edit', 1)
     forge_edit.ForgeEdit()
   endif
   ```

   - Default: auto-enable on forge buffers
   - Disable auto-enable in `vimrc`:

     ```vim
     let g:forge_enable_edit = 0
     ```

2. **Manual command**

   In `plugin/forge.vim`:

   ```vim
   command! -nargs=0 ForgeEdit vim9cmd forge_edit.ForgeEdit()
   ```

   Run in a forge buffer:

   ```vim
   :ForgeEdit
   ```

`ForgeEdit()` checks `&filetype ==# 'forge'` and then sets up the buffer (IDs +
`BufWriteCmd` → `Apply()`).

## Example operations

In a forge buffer, editing lines translates to filesystem operations:

```text
Before:           After (edit):      Operation:
------            --------------     ----------
file.txt          newname.txt        Rename file.txt → newname.txt
olddir/           newdir/            Rename directory
file.txt          (deleted line)     Delete file.txt
                  newfile.txt        Create newfile.txt
                  newdir/            Create directory newdir
file.txt          subdir/file.txt    Move file.txt to subdir/
                  new/file.txt       Create directory new/ (if needed) and new/file.txt
```
