import { TransactionBlock } from '@mysten/sui.js/transactions';
import { useWalletKit } from '@mysten/wallet-kit';
import { ADD_REQUIREMENT_TO_DSTEP } from './Constants';

export default function SendRequirementTransaction(cD : string, type : string, item_id : string,
                                                   wA1 : string, wA2 : string) {
	const { signAndExecuteTransactionBlock } = useWalletKit();

	
	const handleClick = async () => {
		const tx = new TransactionBlock();      // TODO changer la ref un jour
		tx.moveCall({
			target: ADD_REQUIREMENT_TO_DSTEP,
			arguments: [tx.pure(cD), tx.pure(type), tx.pure(item_id), tx.pure(wA1), tx.pure(wA2)],
		});
		await signAndExecuteTransactionBlock({ transactionBlock: tx });
	};

	return (
		<div onClick={handleClick}></div>
	);
}