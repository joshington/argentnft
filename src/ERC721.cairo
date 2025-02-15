

#[starknet::contract]
mod ERC721Contract {
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use zeroable::Zeroable;
    use starknet::contract_address_to_felt252;
    use traits::Into;
    use traits::TryInto;
    use option::OptionTrait;
}

//above imports all necesary library funcs we will need for our contract.

//next is to handle storage variables
#[storage]
struct Storage {
    name: felt252,
    symbol: felt252,
    owners: LegacyMap::<u256, ContractAddress>, 
    balances: LegacyMap::<ContractAddress, u256>,
    token_approvals: LegacyMap::<u256, ContractAddress>,
    operator_approvals: LegacyMap::<(ContractAddress, ContractAddress), bool>,
    token_uri: LegacyMap<u256, felt252>,
}

//events: our contracts will definitely need to emit certain events such as
//Approval, Transfer and ApprovalForAll.to do this we'll need to specify all
//the events in an enum called Event, with custom data types.


#[event]
#[derive(Drop, starknet::Event)]
enum Event {
    Approval: Approval,
    Transfer: Transfer,
    ApprovalForAll: ApprovalForAll
}

//finally we will create these structs, with the memebers being the variables
//to be emitted.

#[derive(Drop, starknet::Event)]
struct Approval {
    owner:ContractAddress,
    to: ContractAddress,
    token_id:u256
}

#[derive(Drop, starknet::Event)]
struct Transfer {
    from:ContractAddress,
    to: ContractAddress,
    token_id: u256
}

#[derive(Drop, starknet::Event)]
struct ApprovalForAll {
    owner:ContractAddress,
    operator: ContractAddress,
    approved:bool
}

//for this erc721 token, we need to initialize certain variables on deployment
//such as the name, and symbol,thus we must implement constructor.


#[constructor]
fn constructor(ref self:ContractState, _name:felt252, _symbol: felt252) {
    self.name.write(_name);
    self.symbol.write(_symbol);
}

//to keep this contract simple, rather than manually implement an interface
//for our NFT, we are simply going to let the compiler automatically
//generate the interface trait by using the `generate _trait` attribute

//we also specify the external[v0] attribute to inform the compiler that the funcs
//cotained within this implementation block are public/external functions

#[external(v0)]
#[generate_trait]
impl IERC721Impl of IERC721Trait {
    //get_name  func returns token name

    fn get_name(self: @ContractState) -> felt252 {
        self.name.read()
    }

    //get_symbol func returns token symbol
    fn get_symbol(self: @ContractState) -> felt252 {
        self.symbol.read()
    }

    //token_uri returns the token uri
    fn get_token_uri(self: @ContractState, token_id: u256) -> felt252 {
        assert(self._exists(token_id), 'ERC721: Invalid token ID');
        self.token_uri.read(token_id)
    }

    //balance_of function returns token balance

    fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
        assert(account.is_non_zero(), 'ERC721: address zero');
        self.balances.read(account)
    }

    //owner_of function returns owner of token_id
    fn owner_of(self: @ContractState, token_id:u256) -> ContractAddress {
        let owner = self.owners.read(token_id);
        assert(owner.is_non_zero(), 'ERC721: invalid token ID');
        owner
    }

    //get_approved function returns approved address for a token

    fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
        assert(self._exists(token_id), 'ERC721: invalid token ID');
        self.token_approvals.read(token_id)
    }

    //is_approved for all function returns approved operator for atoken
    fn is_approved_for_all(self: @ContractState, 
        owner: ContractAddress, operator: ContractAddress) -> bool {
        self.operator_approvals.read((owner, operator))
    }

    //approve function approves an address to spend a token
    fn approve(ref self:ContractState, to:ContractAddress, token_id: u256) {
        let owner =  self.owner_of(token_id);
        assert(to != owner, 'Approval to current owner');
        assert(
            get_caller_address() == owner || self.is_approved_for_all(
                owner, get_caller_address()), 'Not token owner'
        );
        self.token_approvals.write(token_id, to);
        self.emit(
            Approval{ owner:self.owner_of(token_id), to:to, token_id:token_id}
        );
    }

    //set_approval_for_all function approves an operator to spend all tokens
    fn set_approval_for_all(ref self:ContractState, operator:ContractAddress,
        approved:bool
    ) {
        let owner = get_caller_address();
        assert(owner != operator, 'ERC721: approve to caller');
        self.operator_approvals.write((owner, operator), approved);
        self.emit(
            ApprovalForAll{owner: owner, operator:operator, approved:approved}
        );
    }

    //transfer_from function  is used to transfer  a token 
    fn transfer_from(ref self:ContractState, from:ContractAddress, 
        to:ContractAddress, token_id:u256) {
            assert(self._is_approved_or_owner(get_caller_address(), token_id),
                'neitcher owner nor approved'
            );
            self._transfer(from, to, token_id);
        }

    #[generate_trait]
    impl ERC721HelperImpl of ERC721HelperTrait {
        //internal function to check if a token exists
        fn _exists(self: @ContractState, token_id:u256) -> bool {
            //check that owner of token is not zero
            self.owner_of(token_id).is_non_zero()
        }

        // _is_approved _or_owner checks if an address is an approved spend or owner
        fn _is_approved_or_owner(self: @ContractState, spender:ContractAddress,
            token_id: u256
        ) -> bool {
            let owner = self.owners.read(token_id);
            spender == owner 
                || self.is_approved_for_all(owner, spender)
                || self.get_approved(token_id) == spender
        }

        //internal functionthat sets the token uri
        fn _set_token_uri(ref self:ContractState, token_id: u256, token_uri:felt252) {
            assert(self._exists(token_id), 'ERC721: Invalid token ID');
            self.token_uri.write(token_id, token_uri)
        }

        //internal funciton that performs the transfer logic
        fn _transfer(ref self:ContractState, from: ContractAddress, 
            to:ContractAddress, token_id: u256) {
                //check that from address is equal to owner of token
                assert(from == self.owner_of(token_id), 'ERC721:caller is not owner');
                //check that to address is not zero
                assert(to.is_non_zero(), 'ERC721: transfer to 0 address');

                //remove previously made approvals
                self.token_approvals.write(token_id, Zeroable::zero());
                //increase balance of to address, decrease balance of from address
                self.balances.write(from ,self.balances.read(from) - 1.into());
                self.balances.write(to, self.balances.read(to) + 1.into());

                //update token_id owner
                self.owners.write(token_id, to);
                //emit the  TRansfer event

                self.emit(
                    Transfer{ from:from, to: to, token_id:token_id}
                );
            }

            // _mint function mints a new token to the address
            fn _mint(ref self:ContractState, to:ContractAddress, token_id:u256) {
                assert(to.is_non_zero(), 'TO_IS_ZERO_ADDRESS');

                //ensures token_id is unique
                assert(!self.owner_of(token_id).is_non_zero(), 
                
                    'ERC721:Token already minted'
                );
                //increase receiver balance
                let receiver_balance = self.balances.read(to);
                self.balances.write(to, receiver_balance + 1.into());

                //update token_id owner
                self.owners.write(token_id, to);
                //emit Transfer event
                self.emit(
                    Transfer{ from:Zeroable::zero(), to:to, token_id:token_id}
                );
            }
            // _burn function burns token from owners account
            fn _burn(ref self:ContractState, token_id: u256) {
                let owner = self.owner_of(token_id);
                //clear approvals 
                self.token_approvals.write(token_id, Zeroable::zero());
                //decrease owner balance
                let owner_balance = self.balances.read(owner);
                self.balances.write(owner, owner_balance - 1.into());
                //delete owner
                self.owners.write(token_id, Zeroable::zero());
                //emit the Transfer event
                self.emit(
                    Transfer {from:owner, to:Zeroable::zero(), token_id:token_id()}
                );
            }
    }
 
}