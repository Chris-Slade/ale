" Author: farenjihn <farenjihn@gmail.com>, w0rp <devw0rp@gmail.com>
" Description: Lints java files using javac

let s:classpath_sep = has('unix') ? ':' : ';'

let g:ale_java_javac_options = get(g:, 'ale_java_javac_options', '')
let g:ale_java_javac_classpath = get(g:, 'ale_java_javac_classpath', '')

" Detect if the javac command just shows an annoying popup for Mac OSX.
if has('macunix')
    function s:GetIsJavacAnAppStoreStub() abort
        let l:path = resolve(systemlist('which javac')[0])

        for l:line in readfile(l:path)
            " This string is present inside the executable for the popup.
            if l:line =~? 'No Java runtime present'
                return 1
            endif
        endfor

        return 0
    endfunction

    let s:is_javac_an_app_store_stub = s:GetIsJavacAnAppStoreStub()
    delfunction s:GetIsJavacAnAppStoreStub
else
    let s:is_javac_an_app_store_stub = 0
endif

function! ale_linters#java#javac#GetImportPaths(buffer) abort
    let l:pom_path = ale#path#FindNearestFile(a:buffer, 'pom.xml')

    if !empty(l:pom_path) && executable('mvn')
        return ale#path#CdString(fnamemodify(l:pom_path, ':h'))
        \ . 'mvn dependency:build-classpath'
    endif

    return ''
endfunction

function! s:BuildClassPathOption(buffer, import_paths) abort
    " Filter out lines like [INFO], etc.
    let l:class_paths = filter(a:import_paths[:], 'v:val !~# ''[''')
    call map(l:class_paths, 'fnameescape(v:val)')
    call extend(
    \   l:class_paths,
    \   split(ale#Var(a:buffer, 'java_javac_classpath'), s:classpath_sep),
    \)

    return !empty(l:class_paths)
    \   ? '-cp ' . join(l:class_paths, s:classpath_sep)
    \   : ''
endfunction

function! ale_linters#java#javac#GetCommand(buffer, import_paths) abort
    " If running the command will just show a popup, then don't run it.
    if s:is_javac_an_app_store_stub
        return ''
    endif

    let l:cp_option = s:BuildClassPathOption(a:buffer, a:import_paths)
    let l:sp_option = ''

    " Find the src directory, for files in this project.
    let l:src_dir = ale#path#FindNearestDirectory(a:buffer, 'src/main/java')

    if !empty(l:src_dir)
        let l:sp_option = '-sourcepath ' . fnameescape(l:src_dir)
    endif

    " Create .class files in a temporary directory, which we will delete later.
    let l:class_file_directory = ale#engine#CreateDirectory(a:buffer)

    return 'javac -Xlint'
    \ . ' ' . l:cp_option
    \ . ' ' . l:sp_option
    \ . ' -d ' . fnameescape(l:class_file_directory)
    \ . ' ' . ale#Var(a:buffer, 'java_javac_options')
    \ . ' %t'
endfunction

function! ale_linters#java#javac#Handle(buffer, lines) abort
    " Look for lines like the following.
    "
    " Main.java:13: warning: [deprecation] donaught() in Testclass has been deprecated
    " Main.java:16: error: ';' expected

    let l:pattern = '\v^.*:(\d+): (.+):(.+)$'
    let l:symbol_pattern = '\v^ +symbol: *(class) +([^ ]+)'
    let l:output = []

    for l:match in ale#util#GetMatches(a:lines, [l:pattern, l:symbol_pattern])
        if empty(l:match[3])
            " Add symbols to 'cannot find symbol' errors.
            if l:output[-1].text ==# 'error: cannot find symbol'
                let l:output[-1].text .= ': ' . l:match[2]
            endif
        else
            call add(l:output, {
            \   'lnum': l:match[1] + 0,
            \   'text': l:match[2] . ':' . l:match[3],
            \   'type': l:match[2] ==# 'error' ? 'E' : 'W',
            \})
        endif
    endfor

    return l:output
endfunction

call ale#linter#Define('java', {
\   'name': 'javac',
\   'executable': 'javac',
\   'command_chain': [
\       {'callback': 'ale_linters#java#javac#GetImportPaths', 'output_stream': 'stdout'},
\       {'callback': 'ale_linters#java#javac#GetCommand', 'output_stream': 'stderr'},
\   ],
\   'callback': 'ale_linters#java#javac#Handle',
\})
