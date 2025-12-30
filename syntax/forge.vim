vim9script

if exists('b:current_syntax')
  finish
endif

b:current_syntax = 'forge'

syntax match forgeDirectory '^.\+/$'

highlight! default link forgeDirectory Directory
