" File tree plugin
" Demo for using the Vim tree control plugin
" Author: Yegappan Lakshmanan
" Version 0.1
" Last Modified: October 16, 2006

" Use the following command to open a window with a directory listing:
"
"       :FileTreeOpen {dirname}
"
" If {dirname} is not supplied, the current directory is used.
"
if v:version < 700
    finish
endif
if !exists('g:treectrl#available') || g:treectrl#available == 'no'
    finish
endif

let file_tree = g:treectrl#tree.new('[File Explorer]')

" Trick to get the current script ID
map <SID>xx <SID>xx
let s:mysid = substitute(maparg('<SID>xx'), '\(<SNR>\d\+_\)xx$', '\1', '')
unmap <SID>xx

function! s:filetree_select_cb(cur_node)
    let entry = a:cur_node.getCookie()
    if isdirectory(entry)
        " A directory name is selected
        let dir_name = simplify(fnamemodify(entry, ':p'))
        call s:show_dir(dir_name)
    else
        " Open the selected file
        let file_name = simplify(fnamemodify(entry, ':p'))
        let winnum = bufwinnr(file_name)
        if winnum != -1
            exe winnum . 'wincmd w'
        else
            " Jump to the previous window and edit it
            wincmd p
            exe 'edit ' . escape(file_name, ' ')
        endif
    endif
endfunction

function! s:filetree_balloon_cb(cur_node)
    return a:cur_node.getCookie()
endfunction

function! s:filetree_info_cb(cur_node)
    let entry = a:cur_node.getCookie()
    if !isdirectory(entry)
        " Display information about the file
        let file_name = simplify(fnamemodify(entry, ':p'))
        let fsize = getfsize(file_name)
        let ftime = getftime(file_name)
        let fperm = getfperm(file_name)
        return file_name . " [" . fsize .
                    \ " bytes, " . strftime('%c', ftime) .
                    \ ", " . fperm . "]"
    endif

    return ''
endfunction

function! s:filetree_winopen_cb(wnum)
    nnoremap <buffer> <silent> - :call <SID>show_parent_dir()<CR>
endfunction

call file_tree.setCallback({
            \ 'nodeselect' : function(s:mysid . 'filetree_select_cb'),
            \ 'nodeinfo' : function(s:mysid . 'filetree_info_cb'),
            \ 'getballoon' : function(s:mysid . 'filetree_balloon_cb'),
            \ 'winopen' : function(s:mysid . 'filetree_winopen_cb')
            \ })
let detail_help = ['" <enter> - Edit file/directory',
            \ '" <space> - Show information about file' ]
call file_tree.setDetailHelp(detail_help)

function! s:show_parent_dir()
    let root = g:file_tree.getRootNode()
    let dir_node = root.getChildAt(0)

    let dir_name = dir_node.getCookie()

    let dir_name .= '../'

    let parent_dir = fnamemodify(dir_name, ':p')
    if parent_dir == dir_name
        " At the root of the file system
        return
    endif

    call s:show_dir(parent_dir)
endfunction

function! s:show_dir(full_dirname)
    " Remove the existing directory nodes
    let root = g:file_tree.getRootNode()
    call root.removeAllChildren()

    let dir_node = g:treectrl#node.new(a:full_dirname)
    call dir_node.setCookie(a:full_dirname)
    call dir_node.setHighlight('FileTreeHdrName')

    " Get a list of all the files.
    " In the glob() output the last line doesn't end with a \n.
    " So add a explicit \n at the end.
    let files = glob(a:full_dirname . '*') . "\n"
    let files = files . glob(a:full_dirname . '.*') . "\n"

    " Remove the link to the current directory '.'
    let files = substitute(files, "[^\n]\\{-}\\.\n", '', '')

    let dir_list = []
    let file_list = []

    for one_file in split(files, "\n")
        if one_file == ''
            continue
        endif
        if isdirectory(one_file)
            call add(dir_list, one_file)
        else
            call add(file_list, one_file)
        endif
    endfor

    call sort(dir_list)
    call sort(file_list)

    for one_dir in dir_list
        let short_name = fnamemodify(one_dir, ':t') . '/'
        let node = g:treectrl#node.new(short_name)
        call node.setCookie(fnamemodify(one_dir, ':p'))
        call node.setHighlight('FileTreeDirName')
        call dir_node.addChild(node)
    endfor

    for one_file in file_list
        let short_name = fnamemodify(one_file, ':t')
        let node = g:treectrl#node.new(short_name)
        call node.setCookie(fnamemodify(one_file, ':p'))
        call dir_node.addChild(node)
    endfor

    call g:file_tree.addChildNode(root, dir_node)
    "call g:file_tree.windowRefresh()
endfunction

function! s:file_tree_open(...)
    if a:0 == 0
        let dir_name = getcwd()
    else
        let dir_name = a:1
    endif
    let full_dirname = fnamemodify(dir_name, ':p')
    if !isdirectory(full_dirname)
        return
    endif

    if !g:file_tree.isWindowOpen()
        call g:file_tree.windowOpen()
    endif

    highlight clear FileTreeHdrName
    highlight default FileTreeHdrName guibg=Grey ctermbg=darkgray
                \ guifg=white ctermfg=white
    highlight clear FileTreeDirName
    highlight default link FileTreeDirName Directory


    call s:show_dir(full_dirname)
endfunction

command! -nargs=? -complete=dir FileTreeOpen call s:file_tree_open(<f-args>)

