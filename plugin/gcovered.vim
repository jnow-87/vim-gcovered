if exists('g:loaded_gcovered') || &compatible
	finish
endif

let g:loaded_gcovered = 1

" get own script ID
nmap <c-f11><c-f12><c-f13> <sid>
let s:sid = "<SNR>" . maparg("<c-f11><c-f12><c-f13>", "n", 0, 1).sid . "_"
nunmap <c-f11><c-f12><c-f13>


""""
"" global variables
""""
"{{{
let g:gcovered_toggle = get(g:, "gcovered_toggle", "gct")
let g:gcovered_update = get(g:, "gcovered_update", "gcu")
"}}}

""""
"" local functions
""""
"{{{
" \brief	remove leading and trailing whitespaces from string
"
" \param	str		string to strip from
"
" \return	resulting string
function s:strip(str)
	return substitute(a:str, '^\s\+\|\s\+$', '', 'g')
endfunction
"}}}

"{{{
" \brief	try to find a gcov file based on the given source
" 			file name
" 			for a given src file src.cc the following patterns
" 			are used:
" 				src.gcov
" 				src.host.gcov
" 				src.cc.gcov
"
" \param	src_file	the source file name to used as basis
"
" \return	the identified gcov file or an empty string
function s:find_gcov_file(src_file)
	let l:gcov = ""
	let l:ext = split(a:src_file, "\\.")[-1]

	for l:sub in ["gcov", "host.gcov", l:ext . ".gcov"]
		let l:pat = substitute(a:src_file, l:ext . "$", l:sub, "")
		let l:gcov = findfile(l:pat, "**")

		if l:gcov != ""
			break
		endif
	endfor

	return l:gcov
endfunction
"}}}

"{{{
" \brief	add a sign to the buffer identified by file
"
" \param	sign_name	one of the gcovered sign-names
" \param	file		file to place the sign to
" \param	line		line to place the sign to
function s:sign_place(sign_name, file, line)
	exec "sign place 1 line=" . a:line . " name=" . a:sign_name. " file=" . a:file
endfunction
"}}}

"{{{
" \brief	parse the given gcov line
"
" \param	line	line to parse
"
" \return	a 3 element list containing [type, data, covered]
" 				type	a string describing what kind of line has been parsed
" 						"line"		line coverage information
" 						"branch"	branch coverage information
" 						"file"		preamble containing the source file name
" 						""			no relevant information found
"
" 				data	the data associated with the line, depending on type
" 						the following data a returned
" 						"line"		the line number
" 						"branch"	0 (not relevant)
" 						"file"		the source file name
" 						""			0 (not relevant)
"
" 				covered	indicated whether the line indicates covered or not
" 						if type is either "line" or "branch" 0 indicates
" 						not covered while 1 indicates covered
" 						for type "file" or "" 0 is returned (not relevant)
function s:parse_line(line)
	let l:lst = split(a:line, ':')

	" check if the line contains coverage data
	" or other information such as for branches
	if len(l:lst) >= 3
		let l:cov_data = s:strip(l:lst[0])
		let l:line_num = s:strip(l:lst[1])

		if l:cov_data == "-"
			" non-source line
			if l:line_num == 0
				" gcov preamble
				if l:lst[2] == "Source"
					return ["file", l:lst[3], 0]
				endif
			endif

		elseif l:cov_data[0] =~ '[#=$%]'
			" not executed line
			return ["line", l:line_num, 0]
		else
			" executed line
			return ["line", l:line_num, 1]
		endif

	else
		" parse branch line
		if stridx(a:line, "branch") == 0
			if stridx(a:line, "never executed") != -1 || stridx(a:line, " 0%") != -1
				return ["branch", 0, 0]
			else
				return ["branch", 0, 1]
			endif
		endif
	endif

	return ["", 0, 0]
endfunction
"}}}

"{{{
" \brief	return the branch sign that best represents the branch coverage state
"
" \param	state	a string containing of sequence of "0" and "1"
" 					whereas "0" indicates that a branch is not covered
" 					while "1" indicates a covered branch
"
" \return	the gcovered sign-name that represents the given
" 			branch coverage state best
function s:get_branch_sign(state)
	if len(a:state) > 2
		if stridx(a:state, "0") == -1
			return "CovBranchx1"
		elseif stridx(a:state, "1") == -1
			return "CovBranchx0"
		else
			return "CovBranchxx"
		endif

	else
		return "CovBranch" . a:state
	endif
endfunction
"}}}

"{{{
" \brief	parse the given gcov file and create respective signs for the
" 			current buffer
" 			once finished b:cov_file_loaded is set to 1
"
" \param	file	gcov file to parse
function s:load(file)
	let l:cov = readfile(a:file)
	let l:last_line = 0
	let l:branch_cov = ""
	let l:src = ""

	let l:i = 0

	while l:i < len(cov)
		let [l:type, l:data, l:covered] = s:parse_line(l:cov[l:i])

		if l:type == "file"
			let l:src = l:data

		elseif l:type == "line"
			let l:last_line = l:data
			let l:branch_cov = ""

			if l:covered == 1
				call s:sign_place("CovLineCovered", l:src, l:data)
			else
				call s:sign_place("CovLineUncovered", l:src, l:data)
			endif

		elseif l:type == "branch"
			let l:branch_cov .= l:covered

			if len(l:branch_cov) >= 2
				call s:sign_place(s:get_branch_sign(l:branch_cov), l:src, l:last_line)
			endif
		endif

		let l:i = l:i + 1
	endwhile

	let b:cov_file_loaded = 1
endfunction
"}}}

"{{{
" \brief	remove all signs for the given buffer and reset
" 			b:cov_file_loaded to 0
"
" \param	bufname		name of the buffer to cleanup
function s:unload(bufname)
	if b:cov_file_loaded == 0
		return
	endif

	exec "sign unplace * file=" . a:bufname
	highlight SignColumn ctermbg=0

	let b:cov_file_loaded = 0
endfunction
"}}}

"{{{
" \brief	script main function
"
" \param	action	either of "load", "unload", "toggle", "update"
function s:gcovered(...)
	if !exists("b:cov_file_loaded")
		let b:cov_file_loaded = 0
	endif

	if a:1 == "unload" ||( a:1 == "toggle" && b:cov_file_loaded == 1)
		call s:unload(bufname("%"))

	elseif a:1 == "load" || a:1 == "toggle" || a:1 == "update"
		if a:1 == "update"
			call s:unload(bufname("%"))
		endif

		if b:cov_file_loaded == 1
			return
		endif

		if a:0 == 1
			let l:file = s:find_gcov_file(bufname("%"))

			if l:file != ""
				echom "loading gcov file: " . l:file
				call s:load(l:file)
			else
				echoerr "no .gcov file found for " . bufname("%")
			endif
		else
			call s:load(a:2)
		endif

	else
		echoerr "unknown action " . a:1
	endif
endfunction
"}}}

""""
"" command tab-completion
""""
"{{{
let s:cmd_dict = {
	\ "gcovered":{
		\ "load":{"__nested__":"util#complete#file"},
		\ "unload":{},
		\ "toggle":{},
		\ "update":{},
	\ }
\ }


call util#complete#init(s:cmd_dict)
"}}}


""""
"" sign highlighting config
""""
"{{{
highlight default CovLineCovered		ctermfg=28 ctermbg=28
highlight default CovLineUncovered		ctermfg=196 ctermbg=196
highlight default CovBranchCovered		ctermfg=235 ctermbg=28
highlight default CovBranchUncovered	ctermfg=235 ctermbg=196
highlight default CovBranchPartial		ctermfg=235 ctermbg=208
"}}}

""""
"" signs
""""
"{{{
sign define CovLineCovered		text=-- texthl=CovLineCovered
sign define CovLineUncovered	text=-- texthl=CovLineUncovered
sign define CovBranch00			text=✘✘ texthl=CovBranchUncovered
sign define CovBranch10			text=✔✘ texthl=CovBranchPartial
sign define CovBranch01			text=✘✔ texthl=CovBranchPartial
sign define CovBranch11			text=✔✔ texthl=CovBranchCovered
sign define CovBranchx0			text=#✘ texthl=CovBranchUncovered
sign define CovBranchx1			text=#✔ texthl=CovBranchCovered
sign define CovBranchxx			text=#~ texthl=CovBranchPartial
"}}}

""""
"" commands
""""
"{{{
command -nargs=+ -complete=custom,util#complete#lookup Gcovered call s:gcovered(<f-args>)
"}}}

""""
"" mappings
""""
"{{{
call util#map#n(g:gcovered_toggle, ":call " . s:sid . "gcovered('toggle')<cr>", "")
call util#map#n(g:gcovered_update, ":call " . s:sid . "gcovered('update')<cr>", "")
"}}}
