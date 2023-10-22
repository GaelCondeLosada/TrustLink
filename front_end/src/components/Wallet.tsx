import { ConnectButton, useWalletKit } from "@mysten/wallet-kit";

export default function AccountDisplay() {
    return (
        <ConnectButton
        connectText = {'Connect Wallet'}
        />
    );
}