import { TransactionBlock } from '@mysten/sui.js/transactions';
import { useWalletKit } from '@mysten/wallet-kit';
import { NEW_CONTRACT } from './Constants';


export default function SendNCDTransaction() {
	const { signAndExecuteTransactionBlock } = useWalletKit();

	
	const handleClick = async () => {
		const tx = new TransactionBlock();      // TODO changer la ref un jour
		tx.moveCall({
			target: NEW_CONTRACT,
			arguments: [],
		});
		await signAndExecuteTransactionBlock({ transactionBlock: tx });
		window.location.href = '/new_contract';


	};

	return (            
	<button onClick={handleClick} className="start_contract">
	<span className="plus_button">╋</span>
	<span className="button_text">Create New Contract</span>
	</button>
	


	);
}