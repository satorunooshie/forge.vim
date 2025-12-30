vim9script

if exists('g:loaded_forge_vim')
  finish
endif

g:loaded_forge_vim = 1

import autoload 'forge.vim'
import autoload 'edit.vim' as forge_edit

augroup _forge_
  autocmd!
  autocmd BufEnter * call forge#Init()
  autocmd DirChanged * call forge#Chdir()
  autocmd VimEnter * call forge#Startup()
augroup END

# Global command: manually enable edit mode in the current forge buffer.
command! -nargs=0 ForgeEdit vim9cmd forge_edit.ForgeEdit()

nnoremap <silent> <plug>(forge-open) <Cmd> call forge#Open()<CR>
nnoremap <silent> <plug>(forge-up) <Cmd> call forge#Up()<CR>
nnoremap <silent> <plug>(forge-reload) <Cmd> call forge#Reload()<CR>
nnoremap <silent> <plug>(forge-home) <Cmd> call forge#Home()<CR>
nnoremap <silent> <plug>(forge-toggle-hidden) <Cmd> call forge#ToggleHidden()<CR>
