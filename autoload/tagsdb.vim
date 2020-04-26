" Tags database plugin
" Author: Yegappan Lakshmanan
" Version: 0.1
" Last modified: October 17, 2006

" Create and lock a null node
let s:null_tagsdb = {}
lockvar s:null_tagsdb

" Tags database for a file
let tagsdb#tagsdb = {
            \ 'filename' : '',
            \ 'filetype' : '',
            \ 'sort_type' : 'order',
            \ 'tags' : [],
            \ 'bytype' : {},
            \ }

let s:ctags_path = '/users/yega/tools/ctags/bin/ctags'
let s:ctags_opt = ' -f - --format=2 --excmd=pattern --fields=nKs '

" A map between filename and tags db
let s:tags_file_map = {}

" addFile
" Generate tags information for a file. If the file is already present, then
" refresh the tags defined for it.
function! tagsdb#addFile(filename, sort_type)
    let full_filename = fnamemodify(a:filename, ':p')
    let file_db = get(s:tags_file_map, full_filename, {})
    if !empty(file_db)
        " Regenerate the tags information
        call file_db.refresh()
    else
        " Create a new tags db
        let file_db = g:tagsdb#tagsdb.new(full_filename, a:sort_type)
        let s:tags_file_map[full_filename] = file_db
    endif

    return file_db
endfunction

" removeFile
" Remove file filename from the tags db
function! tagsdb#removeFile(filename)
    let full_filename = fnamemodify(a:filename, ':p')
    if has_key(s:tags_file_map, full_filename)
        call remove(s:tags_file_map, full_filename)
    endif
endfunction

" getFile
" Return the tags DB for a file
function! tagsdb#getFile(filename)
    let full_filename = fnamemodify(a:filename, ':p')
    return get(s:tags_file_map, full_filename, {})
endfunction

" new
" Process the tags defined in file file_name
function! tagsdb#tagsdb.new(file_name, sort_type) dict
    let full_name = fnamemodify(a:file_name, ':p')
    if !filereadable(full_name)
        return {}
    endif

    if a:sort_type != 'name' && a:sort_type != 'order'
        return {}
    endif

    let new_db = deepcopy(self)

    unlet new_db.new

    let new_db.filename = full_name
    let new_db.filetype = s:get_filetype(full_name)
    let new_db.sort_type = a:sort_type

    call new_db.refresh()

    return new_db
endfunction

" refresh
" Get or refresh the tags for this file
function! tagsdb#tagsdb.refresh() dict
    let self.tags = []
    let self.bytype = {}

    if self.sort_type == 'name'
        let s:ctags_opt = s:ctags_opt . '--sort=yes '
    else
        let s:ctags_opt = s:ctags_opt . '--sort=no '
    endif

    let cmd_output = system(s:ctags_path . s:ctags_opt . self.filename)
    if cmd_output == '' || v:shell_error != 0
	echomsg "Ctags invocation failed for " . self.filename
	return
    endif

    " Tags with scope information
    let scope_tags = []

    for one_line in split(cmd_output, "\n")
        if one_line == ''
            continue
        endif
        let tag = g:tagsdb#tag.new(one_line)
        call add(self.tags, tag)

        let tag_type = tag.getType()

        if !has_key(self.bytype, tag_type)
            " Create a new tag type
            let self.bytype[tag_type] = []
        endif

        " Store the tag in the tag-type List
        call add(self.bytype[tag_type], tag)

        if tag.scope != ''
            call add(scope_tags, tag)
        endif
    endfor

    " Process the container and member tag information for tags
    " with scope information
    for tag in scope_tags
        let scope = tag.scope
        let scope_type = strpart(scope, 0, stridx(scope, ':'))
        let scope_tag_name = strpart(scope, strridx(scope, ':') + 1)

        let tagtype_list = get(self.bytype, scope_type, [])
        if empty(tagtype_list)
            echomsg 'Scope missing for ' . tag.name . ' (' . tag.scope . ')'
            continue
        endif

        for container_tag in tagtype_list
            if container_tag.name == scope_tag_name
                call add(container_tag.members, tag)
                let tag.container = container_tag
            endif
        endfor
    endfor
endfunction

" getFilename
" Return the filename for the tagsdb
function! tagsdb#tagsdb.getFilename() dict
    return self.filename
endfunction

" getTagtypes
" Get the tag types defined for this file
function! tagsdb#tagsdb.getTagtypes() dict
    return keys(self.bytype)
endfunction

" getTags
" Get the tags defined for this file
function! tagsdb#tagsdb.getTags() dict
    return self.tags
endfunction

" getTagsByType
" Get the tags of particular type in a file
function! tagsdb#tagsdb.getTagsByType(tag_type) dict
    return get(self.bytype, a:tag_type, [])
endfunction

" getTagNearLine
" Get the tag near to the specified line number
function! tagsdb#tagsdb.getTagNearLine(linenum) dict

    let left = 0
    let right = len(self.tags) - 1

    if self.sort_type == 'order'
        " Tags are sorted by chronological order. Do a binary search comparing
        " the line numbers

        " If the line number is the less than the first tag, then no need to
        " search
        if a:linenum < self.tags[0].lnum
            return {}
        endif

        while left < right
            let middle = (right + left + 1) / 2
            let middle_lnum = self.tags[middle].lnum

            if a:linenum == middle_lnum
                let left = middle
                break
            endif

            if middle_lnum > a:linenum
                let right = middle - 1
            else
                let left = middle
            endif
        endwhile
    else
        " Tags are sorted by name. Do a linear search
        let closest_lnum = 0
        let final_left = 0

        " Look for a tag with a line number less than or equal to the supplied
        " line number. If multiple tags are found, then use the tag with the
        " line number closest to the supplied line number. IOW, use the tag
        " with the highest line number.
        while left <= right
            let lnum = self.tags[left].lnum

            if lnum < a:linenum && lnum > closest_lnum
                let closest_lnum = lnum
                let final_left = left
            elseif lnum == a:linenum
                let closest_lnum = lnum
                let final_left = left
                break
            else
                let left += 1
            endif
        endwhile
        if closest_lnum == 0
            return {}
        endif
        if left >= right
            let left = final_left
        endif
    endif

    return self.tags[left]
endfunction

" get_filetype
" Return the filetype for a file
function! s:get_filetype(filename)
    " If the file is loaded in a buffer and the 'filetype' option is set,
    " return it
    if bufexists(a:filename)
        let ftype = getbufvar(a:filename, '&filetype')
        if ftype != ''
            return ftype
        endif
    endif

    " Try to determine the file type by running the filetypedetect autocmd

    " Ignore the filetype autocommands
    let old_eventignore = &eventignore
    set eventignore=FileType

    " Save the 'filetype', as this will be changed temporarily
    let old_filetype = &filetype

    " Run the filetypedetect group of autocommands to determine
    " the filetype
    exe 'doautocmd filetypedetect BufRead ' . a:filename

    " Save the detected filetype
    let ftype = &filetype

    " Restore the previous state
    let &filetype = old_filetype
    let &eventignore = old_eventignore

    return ftype
endfunction

let tagsdb#tag = {
            \ 'name' : '',
            \ 'type' : '',
            \ 'scope' : '',
            \ 'lnum' : 0,
            \ 'pattern' : '',
            \ 'prototype' : '',
            \ 'signature' : '',
            \ 'container' : {},
            \ 'members' : [],
            \ }

" new
" Parse tag_line and crate a new tag entry
function! tagsdb#tag.new(tag_line) dict
    let new_tag = deepcopy(self)
    unlet new_tag.new

    " Extract the tag type
    " The tag type is after the tag prototype field. The prototype field
    " ends with the /;"\t string. We add 4 at the end to skip the characters
    " in this special string..
    let start = strridx(a:tag_line, '/;"' . "\t") + 4
    let end = strridx(a:tag_line, 'line:') - 1
    let new_tag.type = strpart(a:tag_line, start, end - start)

    " Make sure the tag type is valid
    " FIXME: Add a check for whether this tag type is supported for
    " this filetype
    if new_tag.type == ''
        " Line is not in proper tags format
        return new_tag
    endif

    " Extract the tag name
    let new_tag.name = strpart(a:tag_line, 0, stridx(a:tag_line, "\t"))

    " Extract the prototype
    let start = stridx(a:tag_line, '/^') + 2
    let end = stridx(a:tag_line, '/;"' . "\t")
    if a:tag_line[end - 1] == '$'
        let end = end -1
    endif
    let new_tag.prototype = strpart(a:tag_line, start, end - start)
    let new_tag.pattern = '\V\^' . new_tag.prototype .
                \ (a:tag_line[end] == '$' ? '\$' : '')
    let new_tag.prototype = substitute(new_tag.prototype, '\s*', '', '')

    " Extract the tag line number
    let start = strridx(a:tag_line, 'line:')
    let end = stridx(a:tag_line, "\t", start)
    let start += 5
    if end != -1
        let new_tag.lnum = strpart(a:tag_line, start, end - start) + 0
    else
        let new_tag.lnum = strpart(a:tag_line, start) + 0
    endif

    " Extract the tag scope. It is the last field after the
    " 'line:<num>\t' field. The scope information is present only for
    " non-function and non-member tags.
    let new_tag.scope = ''
    if new_tag.type != 'function' && new_tag.type != 'method'
        if end != -1
            let new_tag.scope = strpart(a:tag_line, end + 1)
        endif
    endif

    " Extract the tag signature (if it is present). Signature information
    " is present only for function and method tags
    let new_tag.signature = ''
    if new_tag.type == 'function' || new_tag.type == 'method'
        let start = strridx(a:tag_line, 'signature:')
        if start != -1
            let start += 10
            let end = stridx(a:tag_line, "\t", start)
            if end != -1
                let new_tag.signature = strpart(a:tag_line, start, end - start)
            else
                let new_tag.signature = strpart(a:tag_line, start)
            endif
        endif
    endif

    return new_tag
endfunction

" Tag helper functions
function! tagsdb#tag.getName() dict
    return self.name
endfunction

function! tagsdb#tag.getType() dict
    return self.type
endfunction

function! tagsdb#tag.getPattern() dict
    return self.pattern
endfunction

function! tagsdb#tag.getPrototype() dict
    return self.prototype
endfunction

function! tagsdb#tag.getScope() dict
    return self.scope
endfunction

function! tagsdb#tag.getSignature() dict
    return self.signature
endfunction

function! tagsdb#tag.getLineNum() dict
    return self.lnum
endfunction

function! tagsdb#tag.getMembers() dict
    return self.members
endfunction

function! tagsdb#tag.getContainer() dict
    return self.container
endfunction
