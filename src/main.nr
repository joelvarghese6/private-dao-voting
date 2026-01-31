// Anonymous DAO Voting Contract in Noir
// =====================================
// ZK logic: Only registered members can vote; votes are private;
// double voting is prevented via nullifiers; only the final tally is revealed.

use std::hash::pedersen_hash;

// --- Constants (loop bounds; array sizes use literals 16 and 32) ---
global MAX_MEMBERS: u32 = 16;
global MAX_NULLIFIERS: u32 = 32;

// Operation selector for main dispatcher
global OP_ADD_MEMBER: u8 = 0;
global OP_VOTE: u8 = 1;
global OP_END_VOTE: u8 = 2;
global OP_GET_RESULT: u8 = 3;

// --- Helpers ---

// Compute member commitment: hash(member_secret) used for registration and verification.
fn member_hash(secret: Field) -> Field {
    pedersen_hash([secret])
}

// Compute nullifier for double-vote prevention: hash(member_secret, proposal_id).
fn compute_nullifier(secret: Field, pid: Field) -> Field {
    pedersen_hash([secret, pid])
}

// Prove membership: member_secret hashes to one of the stored member hashes (anonymous).
fn check_membership(secret: Field, member_hashes: [Field; 16]) {
    let my_hash = member_hash(secret);
    let is_member = member_hashes.any(|h| h == my_hash);
    assert(is_member);
}

// Prove this nullifier has not been used before (no double vote).
fn check_nullifier_unused(n: Field, used: [Field; 32]) {
    let already_used = used.any(|u| u == n);
    assert(already_used == false);
}

// Constrain vote_choice to 0 (No) or 1 (Yes). Uses v*(v-1)==0 so v in {0,1}.
fn assert_vote_choice_valid(v: Field) {
    let one_f: Field = 1;
    let v_minus_one = v - one_f;
    let prod = v * v_minus_one;
    let zero: Field = 0;
    assert(prod == zero);
}

// --- Contract logic ---

// Add a new member by storing their hash at the given index.
fn add_member(
    member_hashes: [Field; 16],
    new_hash: Field,
    idx: u32,
) -> [Field; 16] {
    let mut out_hashes = member_hashes;
    out_hashes[idx] = new_hash;
    out_hashes
}

// Anonymous vote: private member_secret and vote_choice; only tally is updated.
fn vote(
    secret: Field,
    v_choice: Field,
    pid: Field,
    yes_votes: Field,
    no_votes: Field,
    active: Field,
    member_hashes: [Field; 16],
    used_nullifiers: [Field; 32],
) -> (Field, Field, Field) {
    assert_vote_choice_valid(v_choice);
    assert(active == 1);
    check_membership(secret, member_hashes);
    let n = compute_nullifier(secret, pid);
    check_nullifier_unused(n, used_nullifiers);
    let one_f: Field = 1;
    let new_yes = yes_votes + v_choice;
    let new_no = no_votes + (one_f - v_choice);
    (new_yes, new_no, n)
}

// End the vote: set active to 0.
fn end_vote(active: Field) -> Field {
    assert(active == 1);
    let z: Field = 0;
    z
}

// Read-only: return current yes/no counts.
fn get_result(y: Field, n: Field) -> (Field, Field) {
    (y, n)
}

// --- Main entrypoint (dispatcher) ---
fn main(
    operation: pub u8,
    member_secret: Field,
    vote_choice: Field,
    proposal_id: pub Field,
    yes_votes: pub Field,
    no_votes: pub Field,
    active: pub Field,
    member_hashes: pub [Field; 16],
    used_nullifiers: pub [Field; 32],
    new_member_hash: pub Field,
    add_member_index: pub u32,
) -> pub (Field, Field, Field, Field) {
    if operation == OP_ADD_MEMBER {
        let _ = add_member(member_hashes, new_member_hash, add_member_index);
        (yes_votes, no_votes, active, 0)
    } else if operation == OP_VOTE {
        let a = vote(
            member_secret,
            vote_choice,
            proposal_id,
            yes_votes,
            no_votes,
            active,
            member_hashes,
            used_nullifiers,
        );
        let new_yes = a.0;
        let new_no = a.1;
        let nullifier = a.2;
        (new_yes, new_no, active, nullifier)
    } else if operation == OP_END_VOTE {
        let new_active = end_vote(active);
        (yes_votes, no_votes, new_active, 0)
    } else if operation == OP_GET_RESULT {
        let r = get_result(yes_votes, no_votes);
        (r.0, r.1, active, 0)
    } else {
        assert(false);
        (0, 0, 0, 0)
    }
}

// --- Tests ---
#[test]
fn test_vote_flow() {
    // Setup: one member (hash of secret 123), empty nullifiers, proposal active
    let member_secret: Field = 123;
    let member_h = member_hash(member_secret);
    let mut member_hashes: [Field; 16] = [0; 16];
    member_hashes[0] = member_h;
    let used_nullifiers: [Field; 32] = [0; 32];
    let proposal_id: Field = 1;
    let yes_votes: Field = 0;
    let no_votes: Field = 0;
    let active: Field = 1;
    let vote_choice: Field = 1; // Yes
    let (new_yes, new_no, nullifier) = vote(
        member_secret,
        vote_choice,
        proposal_id,
        yes_votes,
        no_votes,
        active,
        member_hashes,
        used_nullifiers,
    );
    assert(new_yes == 1);
    assert(new_no == 0);
    assert(nullifier == compute_nullifier(member_secret, proposal_id));
}
