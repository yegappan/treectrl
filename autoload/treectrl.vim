" Generic Vim tree control
" Author: Yegappan Lakshmanan
" Version: 1.0 Beta1
" Last Modified: 22 October 2020
" Copyright: Copyright (C) 2020 Yegappan Lakshmanan
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            treectrl.vim is provided *as is* and comes with no warranty of
"            any kind, either expressed or implied. In no event will the
"            copyright holder be liable for any damamges resulting from the
"            use of this software.
"
if v:version < 700
    " Vim7 is required for the tree control plugin
    finish
endif

if exists('treectrl#available')
    " Already loaded
    finish
endif

let treectrl#available = 'yes'

" Tree control version
let treectrl#version = 100  " 1.0

" Line continuation used here
let s:cpo_save = &cpo
set cpo&vim

" Default do-nothing tree callback function
function! s:default_action(n)
endfunction

" Default window close callback
function! s:default_winclose_cb()
endfunction

" Create and lock a null node
let s:null_node = {}
lockvar s:null_node

" isNullNode
" Check whether a node is a null node
function! treectrl#isNullNode(node)
    return a:node is s:null_node
endfunction

"
" Tree data structure
"
let treectrl#tree = {
            \ 'name' : '',
            \ 'rootnode' : {},
            \ 'windir' : 'vertical',
            \ 'winpos' : 'left',
            \ 'winwidth' : 30,
            \ 'winheight' : 10,
            \ 'vim_winwidth_resize' : 1,
            \ 'foldcolumn_width' : 3,
            \ 'vim_winwidth_chgd' : -1,
            \ 'pre_vim_win_x' : 0,
            \ 'pre_vim_win_y' : 0,
            \ 'vim_win_x' : 0,
            \ 'vim_win_y' : 0,
            \ 'maximized' : 0,
            \ 'bufnum' : 0,
            \ 'lnum' : 0,
            \ 'help_level' : 'brief',
            \ 'brief_help' : [],
            \ 'detail_help' : [],
            \ 'winopen_cb' : function('s:default_action'),
            \ 'winclose_cb' : function('s:default_winclose_cb'),
            \ 'nodeselect_cb' : function('s:default_action'),
            \ 'nodeinfo_cb' : function('s:default_action'),
            \ 'nodeballoon_cb' : function('s:default_action'),
            \ }

" Map between buffer name and tree control
let s:treectrl_buffer_map = {}

" Tree control help text
let s:tree_brief_help = [ '" Press <F1> to display help' ]
let s:tree_detail_help = [
            \ '" x: Zoom-out/Zoom-in window',
            \ '" + : Open a fold',
            \ '" - : Close a fold',
            \ '" * : Open all folds',
            \ '" = : Close all folds',
            \ '" [[ : Jump to previous sibling node',
            \ '" = : Jump to next sibling node',
            \ '" q : Close window',
            \ '" Press <F1> to display help'
            \ ]

" get_tree_ctrl_from_buffer
" Return the tree control for the given buffer number
function! s:get_tree_ctrl_from_buffer(bufnum)
    return get(s:treectrl_buffer_map, a:bufnum, s:null_node)
endfunction

" add_buffer_to_tree_ctrl_map
" Add a buffer name to tree control map
function! s:add_buffer_to_tree_ctrl_map(tree_ctrl)
    let s:treectrl_buffer_map[a:tree_ctrl.bufnum] = a:tree_ctrl
endfunction

" remove_buffer_to_tree_ctrl_map
" Remove a buffer name to tree control map
function! s:remove_buffer_to_tree_ctrl_map(bufnum)
    call remove(s:treectrl_buffer_map, a:bufnum)
endfunction

" Default highlight group for currently selected node in a tree
highlight default link TreeControlNodeSelect Search
highlight default link TreeControlHelp Comment

" new
" Create a new tree and return the tree
function! treectrl#tree.new(tree_name) dict
    let new_tree = deepcopy(self)

    " Escape special characters in the tree name
    let new_tree.name = a:tree_name

    " User cannot create new trees with the new tree instance
    unlet new_tree.new

    let new_tree.rootnode = g:treectrl#node.new('')

    return new_tree
endfunction

" getRootNode
" Return the root node for the tree
function! treectrl#tree.getRootNode() dict
    return self.rootnode
endfunction

" nodePresent
" Checks whether a node is present in the tree or not
" Returns 1 if present, 0 otherwise
function! s:nodePresent(tree, child_node)
    let root_node = a:tree.getRootNode()

    if a:child_node is root_node
        return 1
    endif

    let parent = a:child_node.parent
    while parent isnot s:null_node && parent isnot root_node
        let parent = parent.parent
    endwhile

    return parent is root_node
endfunction

" addChildNode
" Add a child node to parent_node. The new child node is added after the last
" child node. 
function! treectrl#tree.addChildNode(parent_node, child_node) dict
    if a:parent_node is s:null_node
        " Invalid parent node
        return
    endif

    " Make sure the parent node is part of the tree
    if !s:nodePresent(self, a:parent_node)
        return
    endif

    call a:parent_node.addChild(a:child_node)

    call self.windowRefresh()
endfunction

" getNodeDepth
" Get the depth of a given node
function! s:getNodeDepth(tree, child_node)
    let root_node = a:tree.getRootNode()
    let depth = 1

    let parent = a:child_node.parent
    while parent isnot s:null_node && parent isnot root_node
        let depth += 1
        let parent = parent.parent
    endwhile
    return depth
endfunction

" insertAfterNode
" Insert a sibling node after the dest_node
function! treectrl#tree.insertAfterNode(dest_node, new_node) dict
    if !s:nodePresent(self, a:dest_node)
        return
    endif

    call a:dest_node.insertAfter(a:new_node)

    call self.windowRefresh()
endfunction

" insertBeforeNode
" Insert a sibling node before the dest_node
function! treectrl#tree.insertBeforeNode(dest_node, new_node) dict
    if !s:nodePresent(self, a:dest_node)
        return
    endif

    call a:dest_node.insertBefore(a:new_node)

    call self.windowRefresh()
endfunction

" removeNode
" Remove a node from the tree
function! treectrl#tree.removeNode(child_node) dict
    call a:child_node.removeFromParent()

    call self.windowRefresh()
endfunction

" getNodeByLine
" Get the node at the specified line number in the tree window
function! treectrl#tree.getNodeByLine(lnum) dict
    " Make sure the line number is within the tree bounds
    if a:lnum <= self.lnum
        return s:null_node
    endif

    let root_node = self.getRootNode()
    return s:get_node_by_lnum(root_node, self.lnum, a:lnum)
endfunction

" getNodeLineNum
" Return the starting line number of a node in the tree window
function! treectrl#tree.getNodeLineNum(child_node) dict
    if !s:nodePresent(self, a:child_node)
        return 0
    endif

    if a:child_node is self.getRootNode()
        return self.lnum
    endif

    let parent_node = a:child_node.parent
    let parent_lnum = self.getNodeLineNum(parent_node)
    let idx = a:child_node.getIndex()
    let child_offset = s:getChildOffset(parent_node, idx)
    return parent_lnum + child_offset
endfunction

" setName
" Set the name of a node
function! treectrl#tree.setName(child_node, name) dict
    if !s:nodePresent(self, a:child_node)
        return
    endif

    let child_node.name = name
    " Refresh the tree control to show the updated name for the node
    call self.windowRefresh()
endfunction

" highlightNode
" Highlight the node
function! treectrl#tree.highlightNode(child_node) dict
    if !s:nodePresent(self, a:child_node)
        return
    endif

    syntax clear TreeControlNodeSelect
    let lnum = self.getNodeLineNum(a:child_node)
    exe 'syntax match TreeControlNodeSelect /^\%' . lnum . 'l\s*\zs.*/'
endfunction

" enableNode
" Make the node selectable. When <CR> or left-mouse button is double-clicked
" on the node, the select callback is invoked.
function! treectrl#tree.enableNode(child_node) dict
    if !s:nodePresent(self, a:child_node)
        return
    endif

    let a:child_node.enabled = 1
endfunction

" disableNode
" Make the node non-selectable. When <CR> or left-mouse button is
" double-clicked on the node, the select callback is not invoked.
function! treectrl#tree.disableNode(child_node) dict
    if !s:nodePresent(self, a:child_node)
        return
    endif

    let a:child_node.enabled = 0
endfunction

" getBaseParent
" Return the ancestor node of child_node whose parent is the root node
function! treectrl#tree.getBaseParent(child_node) dict
    let root_node = self.getRootNode()

    let parent_node = a:child_node.parent

    while parent_node isnot s:null_node && parent_node isnot root_node &&
                \ parent_node.parent isnot root_node &&
                \ parent_node.parent isnot s:null_node
        let parent_node = parent_node.parent
    endwhile

    if parent_node is s:null_node || parent_node.parent isnot root_node
        return s:null_node
    endif

    return parent_node
endfunction

" foldOpen
" Open the fold used for the child node and its children
function! treectrl#tree.foldOpen(child_node) dict
    if !s:nodePresent(self, a:child_node)
        return
    endif

    let lnum = self.getNodeLineNum(a:child_node)
    exe lnum . 'foldopen!'
endfunction

" foldClose
" Close the fold used for the child node and its children
function! treectrl#tree.foldClose(child_node) dict
    if !s:nodePresent(self, a:child_node)
        return
    endif

    let lnum = self.getNodeLineNum(a:child_node)
    exe lnum . 'foldclose'
endfunction

" setProperty
" Set tree properties. 'prop' should be a dictionary
function! treectrl#tree.setProperty(prop) dict
    if type(a:prop) != type({})
        return
    endif

    if has_key(a:prop, 'windir')
        if a:prop.windir == 'vertical' || a:prop.windir == 'horizontal'
            let self.windir = a:prop.windir
        endif
    endif

    if has_key(a:prop, 'winpos')
        if self.windir == 'vertical' &&
                    \ (a:prop.winpos == 'left' || a:prop.winpos == 'right')
            let self.winpos = a:prop.winpos
        endif
        if self.windir == 'horizontal' &&
                    \ (a:prop.winpos == 'top' || a:prop.winpos == 'bottom')
            let self.winpos = a:prop.winpos
        endif
    endif

    if has_key(a:prop, 'winwidth')
        let self.winwidth = a:prop.winwidth
    endif

    if has_key(a:prop, 'winheight')
        let self.winheight = a:prop.winheight
    endif

    if has_key(a:prop, 'vim_winwidth_resize')
        let self.vim_winwidth_resize = a:prop.vim_winwidth_resize
    endif

    if has_key(a:prop, 'foldcolumn_width')
        let self.foldcolumn_width = a:prop.foldcolumn_width
    endif

    if has_key(a:prop, 'help_level')
        if a:prop.help_level == 'none' ||
                    \ a:prop.help_level == 'brief' ||
                    \ a:prop.help_level == 'detail'
            let self.help_level = a:prop.help_level
        endif
    endif
endfunction

" setBriefHelp
" Setup the brief help text for the tree
" Argument 'brief_help' is a List with each element representing a line
" of text in the help.
function! treectrl#tree.setBriefHelp(brief_help) dict
    " Make sure the help is a List
    if type(a:brief_help) != type([])
        return
    endif
    let self.brief_help = a:brief_help
endfunction

" setDetailHelp
" Setup the detailed help text for the tree
" Argument 'detail_help' is a List with each element representing a line
" of text in the help.
function! treectrl#tree.setDetailHelp(detail_help) dict
    " Make sure the help is a List
    if type(a:detail_help) != type([])
        return
    endif
    let self.detail_help = a:detail_help
endfunction

" setCallback
" Set one or more tree callback functions
function! treectrl#tree.setCallback(cb_dict) dict
    if type(a:cb_dict) != type({})
        return
    endif

    if has_key(a:cb_dict, 'winopen')
        " Set the tree control window open callback function.  The specified
        " function should accept one argument. The argument is the window
        " number of the tree control window.
        if type(a:cb_dict.winopen) == type(function("argc"))
            let self.winopen_cb = a:cb_dict.winopen
        endif
    endif

    if has_key(a:cb_dict, 'winclose')
        " Set the tree control window close callback function.
        if type(a:cb_dict.winclose) == type(function("argc"))
            let self.winclose_cb = a:cb_dict.winclose
        endif
    endif

    if has_key(a:cb_dict, 'nodeselect')
        " Set the node select callback function. The specified function should
        " accept one argument. The argument is the node under the cursor.
        if type(a:cb_dict.nodeselect) == type(function("argc"))
            let self.nodeselect_cb = a:cb_dict.nodeselect
        endif
    endif

    if has_key(a:cb_dict, 'nodeinfo')
        " Set the get node info callback function.  The specified function
        " should accept one argument. The argument is the node under the
        " cursor. The function should return the information to display about
        " the node.
        if type(a:cb_dict.nodeinfo) == type(function("argc"))
            let self.nodeinfo_cb = a:cb_dict.nodeinfo
        endif
    endif

    if has_key(a:cb_dict, 'nodeballoon')
        " Set the get balloon text callback function. The specified function
        " should accept one argument. The argument is the node under the
        " cursor. The function should return the text to display in the
        " balloon.
        if type(a:cb_dict.nodeballoon) == type(function("argc"))
            let self.nodeballoon_cb = a:cb_dict.nodeballoon
        endif
    endif
endfunction

" select_handler
" Invoked when a node is selected in the tree control
function! s:select_handler(tree_ctrl, sel_node)
    if a:sel_node.hlgroup == ''
        " Highlight the currently selected node, only if it is not
        " already highlighted
        call a:tree_ctrl.highlightNode(a:sel_node)
    endif

    " Invoke the callback
    call a:tree_ctrl.nodeselect_cb(a:sel_node)
endfunction

" showinfo_handler
" Invoked to show information about a node
function! s:showinfo_handler(tree_ctrl, sel_node)
    echo a:tree_ctrl.nodeinfo_cb(a:sel_node)
endfunction

" tree_action_handler
" Tree action handler.
function! s:tree_action_handler(action)
    let lnum = line('.')

    let tree_ctrl = s:get_tree_ctrl_from_buffer(bufnr('%'))
    if empty(tree_ctrl)
        return
    endif

    " Get the node under the cursor
    let sel_node = tree_ctrl.getNodeByLine(lnum)
    if sel_node is s:null_node
        return
    endif

    if sel_node.enabled == 0
        " Node is not enabled
        return
    endif

    if a:action == 'select'
        let Action_func = function('s:select_handler')
    elseif a:action == 'showinfo'
        let Action_func = function('s:showinfo_handler')
    endif

    call Action_func(tree_ctrl, sel_node)
endfunction

" Tree_show_balloon
" Display the balloon information for a node
function! Tree_show_balloon()
    let tree_ctrl = s:get_tree_ctrl_from_buffer(v:beval_bufnr)
    if empty(tree_ctrl)
        return ''
    endif

    let cur_node = tree_ctrl.getNodeByLine(v:beval_lnum)
    if cur_node is s:null_node
        return ''
    endif

    if cur_node.enabled == 0
        " Node is not enabled
        return ''
    endif

    if tree_ctrl.nodeballoon_cb == function("s:default_action")
        return cur_node.name
    else
        " Invoke the callback
        let balloon_text =  tree_ctrl.nodeballoon_cb(cur_node)
        if type(balloon_text) != type("")
            " The returned value must be a string
            return ''
        endif
        " Replace tab characters with space.
        let balloon_text = substitute(balloon_text, "\t", ' ', 'g')
        return balloon_text
    endif
endfunction

" tree_move_cursor
" Move the cursor in the specified direction to the next/previous sibling
" node
function! s:tree_move_cursor(dir)
    let tree_ctrl = s:get_tree_ctrl_from_buffer(bufnr('%'))
    if empty(tree_ctrl)
        return
    endif

    let lnum = line('.')

    let cur_node = tree_ctrl.getNodeByLine(lnum)
    if cur_node is s:null_node
        return
    endif

    if a:dir == 'previous'
        let sibling = cur_node.getPrevSibling()
        if sibling is s:null_node
            let sibling = cur_node.parent.getLastChild()
        endif
    else
        let sibling = cur_node.getNextSibling()
        if sibling is s:null_node
            let sibling = cur_node.parent.getChildAt(0)
        endif
    endif

    if sibling isnot s:null_node
        " Move cursor to sibling node
        exe tree_ctrl.getNodeLineNum(sibling)
    endif
endfunction

" tree_zoom_window
" Zoom (maximize/minimize) the tree control window
function! s:tree_zoom_window()
    let tree_ctrl = s:get_tree_ctrl_from_buffer(bufnr('%'))
    if empty(tree_ctrl)
        return
    endif

    if tree_ctrl.maximized
        " Restore the window back to the previous size
        if tree_ctrl.windir == 'horizontal'
            exe 'resize ' . tree_ctrl.winheight
        else
            exe 'vert resize ' . tree_ctrl.winwidth
        endif
        let tree_ctrl.maximized = 0
    else
        " Set the window size to the maximum possible without closing other
        " windows
        if tree_ctrl.windir == 'horizontal'
            resize
        else
            vert resize
        endif
        let tree_ctrl.maximized = 1
    endif
endfunction

" tree_toggle_help
" Toggle the help text from brief to detailed and vice versa
function! s:tree_toggle_help()
    let tree_ctrl = s:get_tree_ctrl_from_buffer(bufnr('%'))
    if empty(tree_ctrl)
        return
    endif

    if tree_ctrl.help_level == 'none'
        " Help text is disabled
        return
    endif

    if tree_ctrl.help_level == 'brief'
        let tree_ctrl.help_level = 'detail'
    else
        let tree_ctrl.help_level = 'brief'
    endif

    call tree_ctrl.windowRefresh()
endfunction

" treectrl_cleanup
" The tree control window is closed. Perform the required cleanup.
function! s:treectrl_cleanup(bufnum)
    let tree_ctrl = s:get_tree_ctrl_from_buffer(a:bufnum)
    if empty(tree_ctrl)
        return
    endif

    " Inform the user plugin that the tree control window is closed
    call tree_ctrl.winclose_cb()

    call s:remove_buffer_to_tree_ctrl_map(a:bufnum)

    let tree_ctrl.bufnum = 0

    if tree_ctrl.windir == 'horizantal' || tree_ctrl.vim_winwidth_resize == 0 ||
                \ tree_ctrl.vim_winwidth_chgd != 1 ||
                \ &columns < (80 + tree_ctrl.winwidth)
        " No need to adjust window width if using horizontally split tree
        " window or if columns is less than 101 or if the user chose not to
        " adjust the window width
    else
        " If the user didn't manually move the window, then restore the window
        " position to the pre-tree control position
        if tree_ctrl.pre_vim_win_x != -1 && tree_ctrl.pre_vim_win_y != -1 &&
                    \ getwinposx() == tree_ctrl.vim_win_x &&
                    \ getwinposy() == tree_ctrl.vim_win_y
            exe 'winpos ' . tree_ctrl.pre_vim_win_x . ' ' .
                        \ tree_ctrl.pre_vim_win_y
        endif

        " Adjust the Vim window width
        let &columns= &columns - (tree_ctrl.winwidth + 1)
    endif

    let tree_ctrl.vim_winwidth_chgd = -1
endfunction

" isWindowOpen
" Is the tree control window currently open?
function! treectrl#tree.isWindowOpen() dict
    if self.bufnum == 0
        return 0
    endif
    let tree_winnum = bufwinnr(self.bufnum)
    return tree_winnum != -1
endfunction

" windowRefresh
" Refresh the tree window by redisplaying the tree control
function! treectrl#tree.windowRefresh() dict
    if !self.isWindowOpen()
        return
    endif

    " Save the current buffer number. Later use this to jump back to
    " the previous window
    let curbufnr = bufnr('%')

    " Go to the tree window
    let tree_winnum = bufwinnr(self.bufnum)
    exe tree_winnum . 'wincmd w'

    " Store the map from buffer name to tree control
    call s:add_buffer_to_tree_ctrl_map(self)

    let save_pos = getpos('.')

    setlocal modifiable

    " Remove the existing contents
    silent %delete _

    syntax clear

    " First display the help at the top of the window
    if self.help_level != 'none'
        let help = self.help_level . '_help'
        let lnum = 0
        if !empty(self[help])
            call append(0, self[help])
            let lnum = len(self[help])
        endif

        call append(lnum, s:tree_{self.help_level}_help)
        let last_line = lnum + len(s:tree_{self.help_level}_help) + 1
        exe 'syntax match TreeControlHelp /\%<' . last_line . 'l.*/'
    endif

    " Display the tree at the end of the buffer
    normal! G
    let self.lnum = line('.')
    call s:node_display(self.rootnode, '')

    silent! %foldopen!

    " Mark the buffer as not modifiable
    setlocal nomodifiable

    " Move the cursor to the previous cursor location
    call setpos('.', save_pos)

    " Need to jump back to the original window only if we are not
    " already in that window
    let wnum = bufwinnr(curbufnr)
    if winnr() != wnum
        exe wnum . 'wincmd w'
    endif
endfunction

" windowInit
" Initialize the tree control window
" Assumes current window is the tree control window
function! treectrl#tree.windowInit() dict
    setlocal noreadonly

    " Folding related settings
    setlocal foldenable
    setlocal foldminlines=0
    setlocal foldmethod=manual
    setlocal foldlevel=9999
    let &l:foldcolumn=self.foldcolumn_width
    setlocal foldtext=v:folddashes.getline(v:foldstart)

    " Mark buffer as scratch
    silent! setlocal buftype=nofile
    silent! setlocal bufhidden=wipe
    silent! setlocal noswapfile
    silent! setlocal nobuflisted

    silent! setlocal nowrap
    silent! setlocal nonumber

    if self.windir == 'vertical'
        setlocal winfixwidth
    else
        setlocal winfixheight
    endif

    " Setup the baloon evaluation related settings
    if has('balloon_eval')
        setlocal balloonexpr=Tree_show_balloon()
        set ballooneval
    endif

    syntax clear

    " Setup the cpoptions properly for the maps to work
    let old_cpoptions = &cpoptions
    set cpoptions&vim

    " Map the standard keys used on the tree
    nnoremap <buffer> <silent> + :silent! foldopen<CR>
    nnoremap <buffer> <silent> - :silent! foldclose<CR>
    nnoremap <buffer> <silent> * :silent! %foldopen!<CR>
    nnoremap <buffer> <silent> = :silent! %foldclose<CR>
    nnoremap <buffer> <silent> <kPlus> :silent! foldopen<CR>
    nnoremap <buffer> <silent> <kMinus> :silent! foldclose<CR>
    nnoremap <buffer> <silent> <kMultiply> :silent! %foldopen!<CR>
    nnoremap <buffer> <silent> [[ :call <SID>tree_move_cursor('previous')<CR>
    nnoremap <buffer> <silent> <BS> :call <SID>tree_move_cursor('previous')<CR>
    nnoremap <buffer> <silent> ]] :call <SID>tree_move_cursor('next')<CR>
    nnoremap <buffer> <silent> <Tab> :call <SID>tree_move_cursor('next')<CR>
    nnoremap <buffer> <silent> x :call <SID>tree_zoom_window()<CR>
    nnoremap <buffer> <silent> <F1> :call <SID>tree_toggle_help()<CR>
    nnoremap <buffer> <silent> q :close<CR>

    " Tree actions
    nnoremap <buffer> <silent> <CR>
                        \ :call <SID>tree_action_handler('select')<CR>
    nnoremap <buffer> <silent> <2-LeftMouse>
                        \ :call <SID>tree_action_handler('select')<CR>
    nnoremap <buffer> <silent> <Space>
                        \ :call <SID>tree_action_handler('showinfo')<CR>

    " Setup autocmds
    autocmd! BufUnload <buffer>
    exe 'autocmd BufUnload <buffer> ' .
                \ ' call s:treectrl_cleanup(expand("<abuf>") + 0)'
    " Display the information about the current node
    autocmd! CursorHold <buffer>
    autocmd CursorHold <buffer> call s:tree_action_handler('showinfo')

    " Restore the previous cpoptions settings
    let &cpoptions = old_cpoptions
endfunction

" windowOpen
" Create a window to display the tree control. If the window is already
" opened, then jump to it. The tree control is displayed in the window.  The
" tree name is used to create the buffer.
function! treectrl#tree.windowOpen() dict
    if !self.isWindowOpen()
        " Tree window doesn't exist. Create a new one.
        let cmd = ''
        if self.windir == 'vertical'
            " Create a vertically split window
            if self.vim_winwidth_resize && self.vim_winwidth_chgd == -1
                " Increase the Vim window width to account for the new
                " tree window (if needed)
                if &columns < (80 + self.winwidth)
                    let self.pre_vim_win_x = getwinposx()
                    let self.pre_vim_win_y = getwinposy()

                    " one extra column is needed for the vertical split
                    let &columns= &columns + self.winwidth + 1

                    let self.vim_winwidth_chgd = 1
                else
                    let self.vim_winwidth_chgd = 0
                endif
            endif
            if self.winpos == 'left'
                let cmd .= 'topleft '
            else
                let cmd .= 'botright '
            endif
            let cmd .= 'vertical ' . self.winwidth
        else
            " Create a horizontally split window
            if self.winpos == 'top'
                let cmd .= 'topleft '
            else
                let cmd .= 'botright '
            endif
            let cmd .= self.winheight
        endif

        let old_isfname = &isfname
        set isfname-=\
        set isfname-=[

        " Speical characters to escape for the tree control buffer name
        if has('win32')
            " On MS-Windows, need to use \\[ to escape the [ character
            let tree_bufname = escape(self.name, ' ')
            let tree_bufname = substitute(tree_bufname, '[', '\\\\[', 'g')
        else
            let tree_bufname = escape(self.name, ' [')
        endif

        let cmd .= 'split ' . tree_bufname
        exe cmd

        let self.bufnum = bufnr('%')

        let &isfname = old_isfname

        let self.vim_win_x = getwinposx()
        let self.vim_win_y = getwinposy()

        " Initialize the window
        call self.windowInit()

        " Invoke the window open callback
        call self.winopen_cb(winnr())
    else
        " Jump to the existing tree window
        exe bufwinnr(self.bufnum) . 'wincmd w'
    endif

    call self.windowRefresh()
endfunction

" windowClose
" Close the tree window
function! treectrl#tree.windowClose() dict
    if !self.isWindowOpen()
        " Tree not displayed in any open window
        return
    endif

    if wnum == winnr()
        " Already in the correct window. Close it
        if winbufnr(2) != -1
            " If only the tree window is opened, then don't close it
            close
        endif
    else
        " Goto the tree window, close it and then come back to the original
        " widow
        let curbufnr = bufnr('%')
        exe wnum . 'wincmd w'
        close
        " Need to jump back to the original window only if we are not
        " already in that window
        let wnum = bufwinnr(curbufnr)
        if winnr() != wnum
            exe wnum . 'wincmd w'
        endif
    endif
endfunction

"
" Tree node data structure
"
" Field descriptions:
" name - Name of the node. Displayed in the tree
" parent - parent node
" children - List of child nodes
" size - total number of children of this node and it's children including
"        this node
" enabled - Node is enabled or disabled. Only enabled nodes respond to the
"           select action.
" hlgroup - Highlight group to use for this node.
" cookie - Application defined cookie data for this node
"
let treectrl#node = {
            \ 'name'   : '',
            \ 'parent' : {},
            \ 'children' : [],
            \ 'size' : 1,
            \ 'enabled' : 1,
            \ 'hlgroup' : '',
            \ 'cookie' : ''
            \ }

" new
" Create a new node
function! treectrl#node.new(node_name) dict
    let new_node = deepcopy(self)

    let new_node.name = a:node_name

    " User cannot create new nodes with the new node instance
    unlet new_node.new
    let new_node.parent = s:null_node

    return new_node
endfunction

" setCookie
" Set the user-plugin cookie data for a node
function! treectrl#node.setCookie(cookie) dict
    let self.cookie = a:cookie
endfunction

" getCookie
" Return the user-plugin cookie data for a node
function! treectrl#node.getCookie() dict
    return self.cookie
endfunction

" setHighlight
" Set the higlight group for a node
function! treectrl#node.setHighlight(hlgroup) dict
    if hlexists(a:hlgroup)
        let self.hlgroup = a:hlgroup
    endif
endfunction

" enable
" Make the node selectable. Responds to <CR> and left-mouse button
" double-clicks
function! treectrl#node.enable() dict
    let self.enabled = 1
endfunction

" disable
" Make the node non-selectable. Doesn't respond to <CR> and left-mouse button
" double-clicks
function! treectrl#tree.disable() dict
    let self.enabled = 0
endfunction

" node_update_parent_size
" Update the size of all the parent nodes for a given node by the specified
" amount. Size can be a positive or negative number.
function! s:node_update_parent_size(child_node, size)
    let parent = a:child_node.parent
    while parent isnot s:null_node
        let parent.size += a:size
        let parent = parent.parent
    endwhile
endfunction

" insertBefore
" Insert a new node before this node
function! treectrl#node.insertBefore(new_node) dict
    if self.parent is s:null_node
        return
    endif
    let idx = self.getIndex()
    call self.parent.insertChildAt(idx, a:new_node)
endfunction

" insertBefore
" Insert a new node after this node
function! treectrl#node.insertAfter(new_node) dict
    if self.parent is s:null_node
        return
    endif
    let idx = self.getIndex()
    call self.parent.insertChildAt(idx + 1, a:new_node)
endfunction

" addChild
" Add a child node to this node
function! treectrl#node.addChild(child_node) dict
    " Add the new child node at the end 
    call self.insertChildAt(len(self.children), a:child_node)
endfunction

" insertChildAt
" Insert a child at the specified index
function! treectrl#node.insertChildAt(idx, child_node) dict
    " Validate the child index.
    let child_idx = a:idx
    if child_idx < 0
        let child_idx = 0
    endif
    if child_idx > len(self.children)
        let child_idx = len(self.children)
    endif

    call insert(self.children, a:child_node, child_idx)
    let a:child_node.parent = self

    " Update the size of all the parent nodes
    call s:node_update_parent_size(a:child_node, a:child_node.size)
endfunction

" getIndex
" Return the index of this node in the parent node
" Returns -1, if there is no parent for this node
function! treectrl#node.getIndex() dict
    let parent_node = self.parent
    if parent_node is s:null_node
        return -1
    endif

    let i = 0
    for child_node in parent_node.children
	if child_node is self
	    return i
	endif
	let i += 1
    endfor

    return -1
endfunction

" getName
" Return the name of the node
function! treectrl#node.getName() dict
    return self.name
endfunction

" getChildByName
" Return the child node with the specified name
function! treectrl#node.getChildByName(name) dict
    for child_node in self.children
	if child_node.name ==# a:name
	    return child_node
	endif
    endfor

    return s:null_node
endfunction

function! treectrl#node.removeChildAt(idx) dict
    let child_node = get(self.children, a:idx, s:null_node)
    if child_node is s:null_node
        return
    endif

    let child_size = child_node.size

    " Reduce the size of the parent nodes
    call s:node_update_parent_size(child_node, -child_size)

    call remove(self.children, a:idx)
endfunction

" removeFromParent
" Remove this node from the parent node
function! treectrl#node.removeFromParent() dict
    if self.parent is s:null_node
        return
    endif

    let idx = self.getIndex()
    if idx == -1
        return
    endif

    call self.parent.removeChildAt(idx)
endfunction

" removeAllChildren
" Remove all the children nodes for this node
function! treectrl#node.removeAllChildren() dict
    let delta = self.size - 1
    let self.children = []
    let self.size = 1
    call s:node_update_parent_size(self, -delta)
endfunction

" getParent
" Return the parent node for this node
function! treectrl#node.getParent() dict
    return self.parent
endfunction

" getChildren
" Return a List of children nodes
function! treectrl#node.getChildren() dict
    return self.children
endfunction

" getChildCount
" Returns the number of children of this node
function! treectrl#node.getChildCount() dict
    return len(self.children)
endfunction

" getChildAt
" Return the child node at index <idx>
function! treectrl#node.getChildAt(idx) dict
    return get(self.children, a:idx, s:null_node)
endfunction

" getLastChild
" Return the last child node
function! treectrl#node.getLastChild() dict
    return get(self.children, -1, s:null_node)
endfunction

" getNextSibling
" Get the next sibling node for this node
function! treectrl#node.getNextSibling() dict
    if self.parent is s:null_node
        return s:null_node
    endif

    let idx = self.getIndex()
    if idx == -1
        return s:null_node
    endif

    return get(self.parent.children, idx + 1, s:null_node)
endfunction

" getPrevSibling
" Get the previous sibling node for this node
function! treectrl#node.getPrevSibling() dict
    if self.parent is s:null_node
        return s:null_node
    endif

    let idx = self.getIndex()
    if idx <= 0
        return s:null_node
    endif

    return get(self.parent.children, idx - 1, s:null_node)
endfunction

" node_display
" Display the node in the tree control window
function! s:node_display(node, indent)
    let new_indent = a:indent
    if a:node.name != ''
        put =a:indent . a:node.name
        if a:node.hlgroup != ''
            " Set the desired higlight
            exe 'syntax match ' . a:node.hlgroup .
                        \ ' /^\%' . line('.') . 'l\s*\zs.*/'
        endif
        let new_indent .= '  '
    endif

    if empty(a:node.children)
        return
    endif

    let node_start_lnum = line('.')
    for child_node in a:node.children
        call s:node_display(child_node, new_indent)
    endfor
    let node_end_lnum = line('.')

    if a:node.name != ''
        " Create the fold for non-root nodes
        exe node_start_lnum . ',' . node_end_lnum . 'fold'
        exe node_start_lnum . ',' . node_end_lnum . 'foldopen!'
    endif
endfunction

" getChildOffset
" Get the offset of a child_node from the parent node.
function! s:getChildOffset(parent_node, child_idx)
    if a:child_idx == 0
        return 1   " First child
    endif

    let offset = 0
    for idx in range(0, a:child_idx - 1)
        let offset += a:parent_node.getChildAt(idx).size
    endfor
    return offset + 1
endfunction

" get_node_by_lnum
" Searches for a node at the specified line number in all the descendant
" nodes of a node.
function! s:get_node_by_lnum(node, node_start_lnum, lnum)
    if a:lnum == a:node_start_lnum
        return a:node
    endif

    " Search in the child nodes

    let node_end_lnum = a:node_start_lnum + a:node.size - 1
    if a:lnum < a:node_start_lnum || a:lnum > node_end_lnum
        " Line number not within the bounds of this node
        return s:null_node
    endif

    let ilnum = a:node_start_lnum + 1 " line number of first child

    for child_node in a:node.children
        let n = s:get_node_by_lnum(child_node, ilnum, a:lnum)
        if n isnot s:null_node
            " Node found
            return n
        endif
        let ilnum += child_node.size " line number of next child
    endfor

    " Not found
    return s:null_node
endfunction

" restore 'cpo'
let &cpo = s:cpo_save
unlet s:cpo_save
