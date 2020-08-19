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

function s:init()
	highlight CovLineCovered		ctermfg=28 ctermbg=28
	highlight CovLineUncovered		ctermfg=196 ctermbg=196
	highlight CovBranchCovered		ctermfg=235 ctermbg=28
	highlight CovBranchUncovered	ctermfg=235 ctermbg=196
	highlight CovBranchPartial		ctermfg=235 ctermbg=208

	sign define CovLineCovered		text=-- texthl=CovLineCovered
	sign define CovLineUncovered	text=-- texthl=CovLineUncovered
	sign define CovBranch00			text=✘✘ texthl=CovBranchUncovered
	sign define CovBranch10			text=✔✘ texthl=CovBranchPartial
	sign define CovBranch01			text=✘✔ texthl=CovBranchPartial
	sign define CovBranch11			text=✔✔ texthl=CovBranchCovered
endfunction

function s:signs_place(sign_name, file, lines, start_id)
	let id = a:start_id

	for line in a:lines
		exec "sign place " . id . " line=" . line . " name=" . a:sign_name. " file=" . a:file
		let id = id + 1
	endfor

	return id
endfunction

function s:signs_create(file_info)
	highlight SignColumn ctermbg=234

	let id = 1

	let id = s:signs_place("CovLineCovered", a:file_info["file"][0], a:file_info["cov_lines"], id)
	let id = s:signs_place("CovLineUncovered", a:file_info["file"][0], a:file_info["uncov_lines"], id)

	let b00 = []
	let b01 = []
	let b10 = []
	let b11 = []

	for line in a:file_info["branches"]
		if index(a:file_info["uncov_branches"], line . ":0") != -1 && index(a:file_info["uncov_branches"], line . ":1") != -1
			let b00 += [line]
		elseif index(a:file_info["uncov_branches"], line . ":0") != -1 && index(a:file_info["cov_branches"], line . ":1") != -1
			let b01 += [line]
		elseif index(a:file_info["cov_branches"], line . ":0") != -1 && index(a:file_info["uncov_branches"], line . ":1") != -1
			let b10 += [line]
		else
			let b11 += [line]
		endif
	endfor

	let id = s:signs_place("CovBranch00", a:file_info["file"][0], b00, id)
	let id = s:signs_place("CovBranch01", a:file_info["file"][0], b01, id)
	let id = s:signs_place("CovBranch10", a:file_info["file"][0], b10, id)
	let id = s:signs_place("CovBranch11", a:file_info["file"][0], b11, id)
endfunction

function s:parse_branch(lines, idx)
	" set branch state (covered or not)
	if stridx(a:lines[a:idx], "never executed") != -1 || stridx(a:lines[a:idx], " 0%") != -1
		let state = "uncov_branches"
	else
		let state = "cov_branches"
	endif

	" find the last line that contains a source line
	" to link the branch with it
	let branch = 0
	let i = a:idx

	while i >= 0
		let i = i - 1

		" parse the line if it is not another branch line
		" otherwise increment the branch counter
		if stridx(a:lines[i], "branch") != 0
			let r = s:parse_line(a:lines, i)

			if r != [] && r[0][-5:-1] == "lines"
				return [state, r[1] . ':' . branch]
			endif
		else
			let branch = branch + 1
		endif
	endwhile

	return []
endfunction

function s:parse_line(lines, idx)
	let lst = split(a:lines[a:idx], ':')

	" check if the line contains coverage data
	" or other information such as for branches
	if len(lst) >= 3
		let cov_data = s:strip(lst[0])
		let src_line = s:strip(lst[1])

		if cov_data == "-"
			" non-source lines
			if src_line == 0
				" gcov preamble
				if lst[2] == "Source"
					return ["file", lst[3]]
				endif
			endif

		elseif cov_data[0] =~ '[#=$%]'
			" not executed line
			return ["uncov_lines", src_line]
		else
			" executed line
			return ["cov_lines", src_line]
		endif
	else
		" parse branch lines
		if stridx(a:lines[a:idx], "branch") == 0
			return s:parse_branch(a:lines, a:idx)
		endif
	endif

	return []
endfunction

function s:load(file)
	let cov = readfile(a:file)
	let file_info = {
		\ "file": [],
		\ "branches": [],
		\ "cov_lines": [],
		\ "cov_branches": [],
		\ "uncov_lines": [],
		\ "uncov_branches": []
	\ }

	let i = 0

	while i < len(cov)
		let r = s:parse_line(cov, i)

		if r != []
			let file_info[r[0]] += [r[1]]

			if r[0][-8:-1] == "branches" && r[1][-1:-1] == "0"
				let file_info["branches"] += [r[1][0:-3]]
			endif
		endif

		let i = i + 1
	endwhile

	echom "src: " . string(file_info["file"])
	echom "lines covered: " . string(file_info["cov_lines"])
	echom "lines not covered: " . string(file_info["uncov_lines"])
	echom "branches: " . string(file_info["branches"])
	echom "branches covered: " . string(file_info["cov_branches"])
	echom "branches not covered: " . string(file_info["uncov_branches"])

	call s:signs_create(file_info)
endfunction

function s:unload(file)
	exec "sign unplace * file=" . a:file
	highlight SignColumn ctermbg=0
endfunction



""""
"" global functions
""""
"{{{
" \brief	execute make, update and show make buffer
"
" \param	...		optional make target
function s:gcovered(...)
	if a:1 == "load"
		call s:load(a:2)
	elseif a:1 == "unload"
		call s:unload(bufname("%"))
	elseif a:1 == "update"
		" TODO
	endif
endfunction
"}}}


call s:init()

""""
"" autocommands
""""
"{{{
"}}}

""""
"" commands
""""
"{{{
command -nargs=+ Gcovered			call s:gcovered(<f-args>)
"}}}
