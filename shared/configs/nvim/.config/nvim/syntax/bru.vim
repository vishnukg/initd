if exists("b:current_syntax")
  finish
endif

" Section headers (keywords that open a block)
syn keyword bruKeyword meta query headers docs tests
syn keyword bruKeyword get post put delete patch options head connect trace
syn match   bruKeyword /\<auth:\(awsv4\|basic\|bearer\|digest\|oauth2\)\>/
syn match   bruKeyword /\<body:\(json\|text\|xml\|sparql\|graphql\|graphql:vars\|form-urlencoded\|multipart-form\)\>/
syn match   bruKeyword /\<body\>/
syn match   bruKeyword /\<vars:\(secret\|pre-request\|post-response\)\>/
syn match   bruKeyword /\<vars\>/
syn match   bruKeyword /\<params:\(query\|path\)\>/
syn match   bruKeyword /\<script:\(pre-request\|post-response\)\>/
syn match   bruKeyword /\<assert\>/

" key: value pairs — key is anything before the colon at line start
syn match bruKey /^\s*\zs[^{}\n][^:]*\ze\s*:/

" template variables  {{foo}}
syn region bruTemplate start=/{{/ end=/}}/

" quoted strings
syn region bruString start=/"/ end=/"/ skip=/\\"/
syn region bruString start=/'/ end=/'/ skip=/\\'/

hi def link bruKeyword  Keyword
hi def link bruKey      Identifier
hi def link bruTemplate Special
hi def link bruString   String

let b:current_syntax = "bru"
