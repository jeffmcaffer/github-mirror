var azure = require('azure-storage')
var blobSvc = azure.createBlobService();

if(process.argv.length != 4) {
    console.log("Must pass global file path then storage name as the only two arguments");
    process.exit(0);
}

blobSvc.createBlockBlobFromLocalFile('msght-azure-storage', process.argv[3], process.argv[2], function (error, result, response) {
    if(error) {
	console.log("Hit error!");
	console.log(error);
    }
});
