" Tag tree plugin
" Author: Yegappan Lakshmanan
" Version 0.1
" Last Modified: October 16, 2006
"
if v:version < 700
    finish
endif

if exists('loaded_tagtree')
    finish
endif
let loaded_tagtree = 1

let tags_tree = g:treectrl#tree.new('[Tags Tree]')

function! s:tagstree_select_cb(cur_node)
    let l = a:cur_node.getCookie()
    if l[0] != 'tag_name'
        return
    endif

    let [node_type, tags_db, tag] = l

    let filename = tags_db.getFilename()
    let searchpat = tag.getPattern()

    " Goto the window containing the file.  If the window is not there, open a
    " new window
    let winnum = bufwinnr(filename)
    if winnum == -1
        " Open the file in the first usable window
        let usable_win = 0
        for i in range(1, winnr('$'))
            if getbufvar(winbufnr(i), '&buftype') == ''
                let usable_win = i
            endif
        endfor

        if usable_win != 0
            " Jump to the file window
            exe usable_win . 'wincmd w'
            exe 'edit ' . escape(filename, ' ')
        else
            exe 'rightbelow vertical split ' . escape(filename, ' ')
        endif
    else
        " If the file is opened in more than one window, then check
        " whether the last accessed window has the selected file.
        " If it does, then use that window.
        let lastwin_bufnum = winbufnr(winnr('#'))
        if bufnr(filename) == lastwin_bufnum
            let winnum = winnr('#')
        endif

        exe winnum . 'wincmd w'
    endif

    " Add the current cursor position to the jump list, so that user can
    " jump back using the ' and ` marks.
    mark '
    silent call search(searchpat, 'w')

    " Bring the line to the middle of the window
    normal! z.

    " If the line is inside a fold, open the fold
    if foldclosed('.') != -1
        .foldopen
    endif
endfunction

function! s:tagstree_balloon_cb(cur_node)
    let l = a:cur_node.getCookie()
    if l[0] != 'tag_name'
        return ''
    endif

    let [node_type, tags_db, tag] = l

    let sig = tag.getSignature()
    if sig != ''
        return tag.getName() . sig
    else
        return tag.getPrototype()
    endif
endfunction

map <SID>xx <SID>xx
let mysid = substitute(maparg('<SID>xx'), '\(<SNR>\d\+_\)xx$', '\1', '')
unmap <SID>xx

call tags_tree.setCallback({
            \ 'nodeselect': function(mysid . 'tagstree_select_cb'),
            \ 'getballoon' : function(mysid . 'tagstree_balloon_cb'),
            \ } )
let brief_help = [ '" Tags Tree' ]
let full_help = [ '" <CR> Select tag',
            \ '" <Space> Show tag info']
call tags_tree.setBriefHelp(brief_help)
call tags_tree.setDetailHelp(full_help)
call tags_tree.setProperty({'help_level':'none'})

function! s:TagsTree_AddTag(container_node, tags_db, tag)
    let tag_node = g:treectrl#node.new(a:tag.getName())
    call tag_node.setCookie(['tag_name', a:tags_db, a:tag])
    call a:container_node.addChild(tag_node)

    for member in a:tag.getMembers()
        call s:TagsTree_AddTag(tag_node, a:tags_db, member)
    endfor
endfunction

function! s:TagsTree_AddAllTags(file_node, tags_db)
    highlight clear TagsTreeTagScope
    highlight default link TagsTreeTagScope Title

    for tag_type in a:tags_db.getTagtypes()
        let tagtype_node = g:treectrl#node.new(tag_type)
        call tagtype_node.setCookie(['tagtype_name'])
        call tagtype_node.setHighlight('TagsTreeTagScope')

        for tag in a:tags_db.getTagsByType(tag_type)
            if empty(tag.getContainer())
                call s:TagsTree_AddTag(tagtype_node, a:tags_db, tag)
            endif
        endfor
        if !empty(tagtype_node.getChildren())
            call a:file_node.addChild(tagtype_node)
            call a:file_node.disable(tagtype_node)
        endif
    endfor
endfunction

function! s:TagsTree_Addfile(fname)
    if !g:tags_tree.isWindowOpen()
        call g:tags_tree.windowOpen()
    endif

    highlight clear TagsTreeFileName
    highlight default TagsTreeFileName guibg=Grey ctermbg=darkgray
                \ guifg=white ctermfg=white

    let full_filename = fnamemodify(a:fname, ':p')

    let tags_db = tagsdb#addFile(full_filename, 'order')

    let root = g:tags_tree.getRootNode()
    for file_node in root.getChildren()
        let [node_type, cookie] = file_node.getCookie()

        if cookie is tags_db
            call file_node.removeAllChildren()
            call s:TagsTree_AddAllTags(file_node, tags_db)
            call g:tags_tree.windowRefresh()
            return
        endif
    endfor

    let file_heading = fnamemodify(full_filename, ':t') . ' [' .
                \ fnamemodify(full_filename, ':h') . ']'

    let file_node = g:treectrl#node.new(file_heading)
    call file_node.setCookie(['file_name', tags_db])
    call file_node.setHighlight('TagsTreeFileName')

    call s:TagsTree_AddAllTags(file_node, tags_db)

    call g:tags_tree.addChildNode(g:tags_tree.getRootNode(), file_node)
endfunction

function! s:TagsTree_Removefile(fname)
    let full_filename = fnamemodify(a:fname, ':p')

    let file_db = tagsdb#getFile(full_filename)
    if empty(file_db)
        return
    endif

    call tagsdb#removeFile(full_filename)

    let root = g:tags_tree.getRootNode()
    for file_node in root.getChildren()
        let [node_type, cookie] = file_node.getCookie()

        if cookie is file_db
            call g:tags_tree.removeNode(file_node)
            return
        endif
    endfor
endfunction

function! s:TagTree_ShowNearTag()
    let fname = expand('%')
    let file_db = tagsdb#getFile(fname)
    if empty(file_db)
        return
    endif

    let lnum = line('.')
    let tag = file_db.getTagNearLine(lnum)
    if empty(tag)
        echo 'No tag found'
    else
        echo 'Tag: '. tag.getName()
    endif
endfunction

command! -nargs=* -complete=file TagTreeAdd call s:TagsTree_Addfile(<f-args>)
command! -nargs=* -complete=file TagTreeRemove
            \ call s:TagsTree_Removefile(<f-args>)

command! -nargs=* TagTreeShowTag call s:TagTree_ShowNearTag()
