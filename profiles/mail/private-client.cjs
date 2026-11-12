"use strict";
const fs=require("node:fs"),net=require("node:net");
// Read-only descriptor: application backend ownership is never imported.
function render(service,clientAddress) {
 const M=require("./consumer.cjs").api(),checked=M.validateMailService(service);
 if(!checked.valid||net.isIP(clientAddress)!==4)throw Error("MAIL_PRIVATE_CLIENT_ADDRESS_INVALID");
 const plan=M.planMailService(checked.normalized),endpoint=plan.private_endpoint;
 const [base,bits]=checked.normalized.networks.edge_subnet.split("/"),number=ip=>ip.split(".").reduce((a,b)=>a*256+Number(b),0),first=number(base),last=first+2**(32-Number(bits))-1,value=number(clientAddress);
 if(value<=first||value>=last||clientAddress===endpoint.address||clientAddress===checked.normalized.networks.edge_gateway)throw Error("MAIL_PRIVATE_CLIENT_ADDRESS_INVALID");
 return {network:{external:true,name:endpoint.network},attachment:{ipv4_address:clientAddress},submission:{host:endpoint.hostname,address:endpoint.address,port:endpoint.port,starttls:"required",verify_peer:true,authentication:"required"}};
}
module.exports={render};
if(require.main===module)console.log(JSON.stringify(render(JSON.parse(fs.readFileSync(process.argv[2])).service,process.argv[3])));
