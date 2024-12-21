local option_spec = require"src_lua.texrunner.option_spec".spec

-- outputs a table of all registered options/arguments.
-- outputformat is suitable for markdown. You can also display this as nice
-- table by piping the output into
-- `column -t -s " | " -L`

print("| "..table.concat({"optname", "long", "short", "default"}, " | ").." |")
print("| "..table.concat({"-------", "----", ":---:", "-------"}, " | ").." |")

local out = {}
for optname, v in pairs(option_spec) do
	local p = {optname}

	if v.long then
		local pe = v.long
		if v.default then pe = pe.."[" end
		if v.param   then pe = pe.."="..optname end
		if v.default then pe = pe.."]" end
		table.insert(p, pe)
	else
		table.insert(p, "-")
	end

	if v.short then
		local pe = v.short
		if v.default then pe = pe.."[" end
		if v.param   then pe = pe.."="..optname end
		if v.default then pe = pe.."]" end
		table.insert(p, pe)
	else
		table.insert(p, "-")
	end

	if v.default then
		table.insert(p, v.default)
	else
		table.insert(p, "-")
	end

	table.insert(out, "| "..table.concat(p, " | ").." |")
end
table.sort(out)

print(table.concat(out, "\n"))

io.stderr:write[[\begin{longtable}{llcX}
	\toprule
	optname & long & short & default \\\midrule
]]
io.stderr:write(table.concat(out, "\n"):gsub(" | ", " & "):gsub("| ", ""):gsub(" |", [[ \\]]):gsub("_", "\\_"), "\n")
io.stderr:write[[\bottomrule
\end{longtable}]]
