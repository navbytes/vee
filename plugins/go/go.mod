// The module path is the repository path so a plugin author can depend on the
// SDK directly:
//
//	go get github.com/navbytes/vee/plugins/go
//
// Go plugins compile to a binary, so unlike the TypeScript and Python SDKs
// there is nothing to vendor beside the plugin — the module is the delivery
// mechanism.
module github.com/navbytes/vee/plugins/go

go 1.21
