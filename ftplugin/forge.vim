vim9script

if exists('b:did_ftplugin')
  finish
endif

b:did_ftplugin = 1

if !hasmapto('<Plug>(forge-open)', 'n')
  nmap <buffer> <CR> <Plug>(forge-open)
endif
if !hasmapto('<Plug>(forge-up)', 'n')
  nmap <buffer> - <Plug>(forge-up)
endif
if !hasmapto('<Plug>(forge-toggle-hidden)', 'n')
  nmap <buffer> . <Plug>(forge-toggle-hidden)
endif
if !hasmapto('<Plug>(forge-home)', 'n')
  nmap <buffer> ~ <Plug>(forge-home)
endif
if !hasmapto('<Plug>(forge-reload)', 'n')
  nmap <buffer> \\ <Plug>(forge-reload)
endif
