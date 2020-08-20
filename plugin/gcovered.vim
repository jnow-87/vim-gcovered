if exists('g:loaded_gcovered') || &compatible
	finish
endif

let g:loaded_gcovered = 1

" get own script ID
nmap <c-f11><c-f12><c-f13> <sid>
let s:sid = "<SNR>" . maparg("<c-f11><c-f12><c-f13>", "n", 0, 1).sid . "_"
nunmap <c-f11><c-f12><c-f13>


""""
"" highlighting config
""""
"{{{
highlight default CovLineCovered		ctermfg=28 ctermbg=28
highlight default CovLineUncovered		ctermfg=196 ctermbg=196
highlight default CovBranchCovered		ctermfg=235 ctermbg=28
highlight default CovBranchUncovered	ctermfg=235 ctermbg=196
highlight default CovBranchPartial		ctermfg=235 ctermbg=208
"}}}

""""
"" global variables
""""
"{{{
"}}}

""""
"" local variables
""""
"{{{
"}}}

""""
"" local functions
""""
function s:strip(str)
	return substitute(a:str, '^\s\+\|\s\+$', '', 'g')
endfunction

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

function s:sign_place(sign_name, file, line)
	exec "sign place 1 line=" . a:line . " name=" . a:sign_name. " file=" . a:file
endfunction

function s:parse_line(line)
	let l:lst = split(a:line, ':')

	" check if the line contains coverage data
	" or other information such as for branches
	if len(l:lst) >= 3
		let l:cov_data = s:strip(l:lst[0])
		let l:src_line = s:strip(l:lst[1])

		if l:cov_data == "-"
			" non-source line
			if l:src_line == 0
				" gcov preamble
				if l:lst[2] == "Source"
					return ["file", l:lst[3], 0]
				endif
			endif

		elseif l:cov_data[0] =~ '[#=$%]'
			" not executed line
			return ["line", l:src_line, 0]
		else
			" executed line
			return ["line", l:src_line, 1]
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

function s:load(file)
	let l:cov = readfile(a:file)
	let l:last_line = 0
	let l:branch = ""
	let b:cov_srcfile = ""

	let l:i = 0

	while l:i < len(cov)
		let [l:type, l:data, l:covered] = s:parse_line(l:cov[l:i])

		if l:type == "file"
			let b:cov_srcfile = l:data

		elseif l:type == "line"
			let l:last_line = l:data
			let l:branch_cov = ""

			if l:covered == 1
				call s:sign_place("CovLineCovered", b:cov_srcfile, l:data)
			else
				call s:sign_place("CovLineUncovered", b:cov_srcfile, l:data)
			endif

		elseif l:type == "branch"
			let l:branch .= l:covered

			if len(l:branch) >= 2
				call s:sign_place(s:get_branch_sign(l:branch), l:src, l:last_line)
			endif
		endif

		let l:i = l:i + 1
	endwhile

	let b:cov_file_loaded = 1
endfunction

function s:unload(bufname)
	if b:cov_file_loaded == 0
		return
	endif

	exec "sign unplace * file=" . a:bufname
	highlight SignColumn ctermbg=0

	let b:cov_file_loaded = 0
endfunction

""""
"" global functions
""""
" \brief	execute make, update and show make buffer
"
" \param	...		optional make target
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

let s:cmd_dict = {
	\ "gcovered":{
		\ "load":{"__nested__":"util#complete#file"},
		\ "unload":{},
		\ "toggle":{},
		\ "update":{},
	\ }
\ }


call util#complete#init(s:cmd_dict)


""""
"" signs
""""

sign define CovLineCovered		text=-- texthl=CovLineCovered
sign define CovLineUncovered	text=-- texthl=CovLineUncovered
sign define CovBranch00			text=✘✘ texthl=CovBranchUncovered
sign define CovBranch10			text=✔✘ texthl=CovBranchPartial
sign define CovBranch01			text=✘✔ texthl=CovBranchPartial
sign define CovBranch11			text=✔✔ texthl=CovBranchCovered


""""
"" autocommands
""""
"{{{
"}}}
sign define CovBranchx0			text=#✘ texthl=CovBranchUncovered
sign define CovBranchx1			text=#✔ texthl=CovBranchCovered
sign define CovBranchxx			text=#~ texthl=CovBranchPartial

""""
"" commands
""""
"{{{
command -nargs=+ -complete=custom,util#complete#lookup Gcovered call s:gcovered(<f-args>)
"}}}
