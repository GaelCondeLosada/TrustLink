import './new_contract.css'
import SendRequirementTransaction from './SendRTransaction'
import { TransactionBlock } from '@mysten/sui.js/transactions';
import { useWalletKit } from '@mysten/wallet-kit';
import { ADD_ACTION_TO_DSTEP, VALIDATE_STEP } from './Constants'

export default function NewActionDisplay() {

    const CD = '0xec5d4aa57a6c7f3aa0630ec49f699a844df3c744d598e1ee29a6cf968a9b2c46'
    const RANDOM_ID = "0xb2f05e3c676d7e2b463de8a2c37218ad90ed8cf3e7dbffb62c59da598aa2f73b";


    const { signAndExecuteTransactionBlock } = useWalletKit();

	
	const handleClick1 = async () => {
		const tx = new TransactionBlock();      
		tx.moveCall({
			target: VALIDATE_STEP,
			arguments: [tx.pure(CD)],
		});
		await signAndExecuteTransactionBlock({ transactionBlock: tx });
	};
    
    const handleClick2 = async (cd : string, type:string,  wA : string, item_id1 : string, item_id2 : string) => {
		const tx = new TransactionBlock();      
		tx.moveCall({
			target: ADD_ACTION_TO_DSTEP,
			arguments: [tx.pure(CD),tx.pure(type), tx.pure(wA), tx.pure(item_id1), tx.pure(item_id2)],
		});
		await signAndExecuteTransactionBlock({ transactionBlock: tx });
	};


    const w3_open = () => {
        let up_bar = document.getElementById("main_upper_bar");
        if (up_bar != null){
            up_bar.style.marginLeft = "25%";
        } 
        let side_bar = document.getElementById("mySidebar");
        if (side_bar != null){
            side_bar.style.width = "25%";
            side_bar.style.display = "block";
        }
    }


    const w3_close = () => {
        let up_bar = document.getElementById("main_upper_bar");
        if (up_bar != null) { up_bar.style.marginLeft = "0%";}

        let side_bar = document.getElementById("mySidebar");
        if (side_bar != null) { side_bar.style.display = "none";}
    }

    const drop = (e: any) => {
        e.preventDefault();
    }

    const drag = (event: any) => {
            event.preventDefault();
            var data = event.dataTransfer.getData("text");
            var item = document.createElement("div");
            item.className = "item";
            item.innerHTML = data;
            var deleteIcon = document.createElement("i");
            deleteIcon.textContent = "X";
            //deleteIcon.className = "fas fa-trash";
            deleteIcon.addEventListener('click', function() {
                item.remove();
            });
            item.appendChild(deleteIcon);
            event.target.appendChild(item);
        }
        
        var items = document.querySelectorAll('.item');
        items.forEach(function(item) {
            item.addEventListener('dragstart', function(event) {
                //event.dataTransfer.setData("text", event.target.outerHTML);
                
            });
        });

    
    const sendInfo =async (contractDescriptor: string, type : string, wA : string,
                           item_id1 : string, item_id2 : string) => {
        var div = document.createElement("div");
        div.className = "item";
        div.innerHTML = "Some Condition " + type;
        var right = document.getElementById("dropable");
        if (right != null){
            right.appendChild(div);
        }
        
        handleClick2(contractDescriptor, type, wA, item_id1, item_id2);


    }    
    


    const submit_fields0 = () => {
        var item_id = document.getElementById("item_id0") as HTMLInputElement | null;
        var wallet_addr = document.getElementById("wallet_addr0") as HTMLInputElement | null;
        
        if (item_id != null && wallet_addr != null){
            sendInfo(CD, "100", wallet_addr.value, RANDOM_ID, RANDOM_ID)
        }
        var div = document.getElementById("0");
        if (div != null){
            for (var i = 0; i < 3; i++){
                div.removeChild(div.children[0])
            }
        }
    } 

    const submit_fields1 = () => {
        var item_id = document.getElementById("item_id1") as HTMLInputElement | null;
        var wallet_addr = document.getElementById("wallet_addr1") as HTMLInputElement | null;
        if (item_id != null && wallet_addr != null){
            //sendInfo(PATH, "101", "0x6", item_id.value, "0x6")
        }
        var div = document.getElementById("1");
        if (div != null){
            for (var i = 0; i < 3; i++){
                div.removeChild(div.children[0])
            }
        }
    }
    
    const submit_fields2 = () => {      // TODOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
        var item_id = document.getElementById("item_id2") as HTMLInputElement | null;
        var wallet_addr = document.getElementById("wallet_addr2") as HTMLInputElement | null;
        if (item_id != null && wallet_addr != null){
            //sendInfo(PATH, "2", "0x0", wallet_addr.value, "0x0")
        }
        var div = document.getElementById("2");
        if (div != null){
            for (var i = 0; i < 3; i++){
                div.removeChild(div.children[0])
            }
        }
    }


    const selectCondition0 = () => {
        var button = document.getElementById("0");
        var left = document.getElementById("left");
        if (button != null && left != null){
            if (button.children.length >= 2){
                return
            }
            var input1 = document.createElement("input");
            var input2 = document.createElement("input");
            input1.name = "item_id"
            input1.id = "item_id0"
            input2.name = "wallet_addr"
            input2.id = "wallet_addr0"
            input1.placeholder = "item id"
            input2.placeholder = "wallet address"
            var confirm = document.createElement("button")
            confirm.textContent = "Confirm"
            confirm.style.position = "relative"
            confirm.style.float = "right"
            confirm.type = "submit"
            confirm.onclick = submit_fields0
            button.appendChild(input1)
            button.appendChild(input2)
            button.appendChild(confirm)
            
    
        }
        //window.location.href = '/requirements?id=0'
    }

    const selectCondition1 = () => {
        var button = document.getElementById("1");
        var left = document.getElementById("left");
        if (button != null && left != null){
            if (button.children.length >= 2){
                return
            }
            var input1 = document.createElement("input");
            var input2 = document.createElement("input");
            input1.name = "item_id"
            input1.id = "item_id1"
            input2.name = "wallet_addr"
            input2.id = "wallet_addr1"
            input1.placeholder = "item id"
            input2.placeholder = "wallet address"
            var confirm = document.createElement("button")
            confirm.textContent = "Confirm"
            confirm.style.position = "relative"
            confirm.style.float = "right"
            confirm.type = "submit"
            confirm.onclick = submit_fields1
            button.appendChild(input1)
            button.appendChild(input2)
            button.appendChild(confirm)
            
    }}

    const selectCondition2 = () => {
        var button = document.getElementById("2");
        var left = document.getElementById("left");
        if (button != null && left != null){
            if (button.children.length >= 2){
                return
            }
            var input1 = document.createElement("input");
            var input2 = document.createElement("input");
            input1.name = "item_id"
            input1.id = "item_id2"
            input2.name = "wallet_addr"
            input2.id = "wallet_addr2"
            input1.placeholder = "item id"
            input2.placeholder = "wallet address"
            var confirm = document.createElement("button")
            confirm.textContent = "Confirm"
            confirm.style.position = "relative"
            confirm.style.float = "right"
            confirm.type = "submit"
            confirm.onclick = submit_fields2
            button.appendChild(input1)
            button.appendChild(input2)
            button.appendChild(confirm)
    }}

    const finalize = () => {
        handleClick1()
    }
    

    
    

    


    


    return (
        <body>
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.2.0/css/all.min.css"/>
            <script src="https://ajax.googleapis.com/ajax/libs/jquery/2.1.1/jquery.min.js"></script>
    <script src="https://cdn.rawgit.com/harvesthq/chosen/gh-pages/chosen.jquery.min.js"></script>
    <link href="https://cdn.rawgit.com/harvesthq/chosen/gh-pages/chosen.min.css" rel="stylesheet"/>
    <script src='./new_contract.js'/>


<div className="envelope">

    <div className="sidebar w3-bar-block w3-card w3-animate-left" style={ {display: "none"} } id="mySidebar">
          <button className="w3-bar-item w3-button w3-large"
          onClick={w3_close}>Close &times;</button>
          <a href="#" className="w3-bar-item w3-button">Link 1</a>
          <a href="#" className="w3-bar-item w3-button">Link 2</a>
          <a href="#" className="w3-bar-item w3-button">Link 3</a>
        </div>

    <div id="main_upper_bar">

        <div className="w3" id="main_text">
            <button id="openNav" className="w3-button w3 w3-xlarge" onClick={w3_open}>&#9776;</button>
            Trustlink
            <img src="/logo_no_text.png" className="trustlinks_pic"/>
        </div>

    </div>

    <h2 className="contract_title">Design Your Contract</h2>

    <div className="container">
        <div className="left" id="left">
            <h3 className="title">Available Contract Template</h3>
            <div className="item" id="0" onClick={selectCondition0}>GIVE ITEM</div>
            <div className="item" id="1" onClick={selectCondition1}>UNLOCK ITEM</div>
            <div className="item" id="2" onClick={selectCondition2}>SWAP</div>
        </div>
        <div className="right">
            <h3 className="title">Your New Contract</h3>
            <div className="droppable" id="dropable" onDrop={drop} onDragOver={drag}></div>
        </div>
    </div>

    <div className="form">
            
            <div>
                <button className="submit" onClick={ finalize }>Finalize step</button>
            </div>

        
    </div>

    </div>
        

        
</body>

    );
}