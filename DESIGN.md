Neovim:
- Provide a `neovim-plugin` module which lets us standardize the interface for exporting plugins.
	- Should include the target neovim version.
	- Should allow you to target multiple neovim versions with different function compatibility?
	- These could pass in the vim function so that you don't have to worry about compatibility.
- Should take a keymapping

Static analysis:

- Should not run arbitrary code in the top level on require?
	- Implies that initialization should go into a setup() function.
