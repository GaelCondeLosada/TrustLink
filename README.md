
## TrustLink 

The module defines smart contract structures and functions for managing trusted exchanges. It allows users to create, modify, and interact with contracts that involve specific requirements and actions.


## Trusted Exchange Contracts: 

The primary use case for this code is to facilitate trusted exchanges between participants. A trusted exchange typically involves multiple parties, each with specific roles and requirements, and this code helps manage such contracts.

- *Modular Smart Contract Management*: The code provides a modular framework for managing smart contracts. It defines various structures and functions that allow users to create, modify, and interact with contracts in a structured and organized manner.

- *Requirements and Actions*: The code defines a framework for specifying requirements and actions within a contract. This can be used in various scenarios, such as conditional transfers of assets, confirming specific steps, or locking/unlocking items.

- *Expiration Handling*: Contracts often have time-sensitive components. This code allows you to specify expiration times and actions to be taken when a contract reaches its expiration.

- *Item Management*: The code handles the management of items or assets within the contract. Users can put items into the contract, retrieve items if they have the rights, lock items, or check if items are locked.

- *Confirmation Mechanism*: The code supports a confirmation mechanism where participants can confirm certain steps within the contract. This is useful for multi-party agreements where consensus or verification is required.


## Structures

**Structure Architecture and Links**
![Image 22-10-2023 at 08 56](https://github.com/GaelCondeLosada/TrustLink/assets/100673718/15eb4dc3-b017-4a4a-96f9-acfe82d94adc)




### TrustedContract
- Represents the main contract structure.
- Manages a trusted exchange.
- Contains information about the contract's creation time, expiration time, contract steps, expiration actions, and more immutably.
- Once deployed the contract can **never** be changed.
### TrustedContractHandler
- Contains a table of items, confirmations, keys, and utility options for methods.
- Needs to be mutable to manage contract states and always follows the immutables rules set by his corresponding trusted contract
### ContractState
- Wrapper for the index that represents the contract's state.
- Contains information about the current step, whether the contract is finished, and whether it's expired.
### ContractDescriptor
- Describes each step of a contract.
- Mutable during the setup phase and and used to create the immutable rules of the trusted contract.
- Contains steps, expiration actions, and expiration time.
### ContractStep
- Describes each step of a contract.
- Contains requirements and actions for a step.
- A contract is composed of a sequence of ContractStep that all needs to be checked in order to validate the contract.
### Requirement
- Represents a requirement to be fulfilled by contract participants.
- Contains type, item ID, and wallet addresses to describe the requirement.
- Can be added to the descriptor by the user depending on his needs.
### Action
- Represents an action that will be executed by the contract.
- Contains type, wallet address, and item IDs to describe the action.
- - Can be added to the descriptor by the user depending on his needs.
### ItemContainer
- Wraps a contained item with information about its owner and lock status.
- Once locked the original owner can no longer retrieve until it is unlocked by the contract
### ConfirmationKey
- Represents a key that allows a bridge to real life use.
- The confirmation key can be given to a party by the original owner that locked it's asset to a safe handled by the contract

## Creation of a Contract using TrustLink's API
![Image 22-10-2023 at 09 13](https://github.com/GaelCondeLosada/TrustLink/assets/100673718/f14667f3-d213-402b-898c-7c0d7059636a)


### Available Functions 

- new_contract_descriptor: Create a new contract descriptor.
- validate_step: Validate the current step and create a new step for adding requirements and actions.
- add_requirement_to_description_step: Add a requirement to the current step.
- add_action_to_description_step: Add an action to the current step.
- add_expiration_action_to_description: Add an expiration action.
- add_expiration_time_to_description: Set the expiration time.
- new_contract: Create a new contract from a contract descriptor.
- put_item: Add an item to the contract.
- take_item: Retrieve an item from the contract.
- borrow_item_mut: Borrow a mutable reference to an item inside the contract.
- lock_item: Lock an item inside the contract.
- is_item_locked: Check if an item in the contract is locked.
- contains_item: Check if the contract contains a specific item.
- confirm_step: Confirm a step in the contract.
- confirmate_step_with_key: Confirm a step using a key.
- cancel_contract: Cancel the contract and return items to their owners.
