pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebIncentives.sol";

contract GebIncentivesTest is DSTest {
    GebIncentives incentives;

    function setUp() public {
        incentives = new GebIncentives();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
