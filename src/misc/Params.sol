// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

contract Params {
    
    event DepositParamsSetup (address indexed user, 
                              uint256 _minDepositAmount,
                              uint256 _maxDepositAmount,
                              uint256 _depositFee,
                              uint256 _minLockupPeriod,
                              uint256 _maxLockupPeriod);

    event BorrowParamsSetup (address indexed user,
                              uint256 _minBorrowAmount,
                              uint256 _maxBorrowAmount,
                              uint256 _borrowFee,
                              uint256 _minRepaymentPeriod,
                              uint256 _maxRepaymentPeriod,
                              uint256 _baseRate,
                              uint256 _reserveFactor,
                              uint256 _maxInterestRate,
                              uint256 _minInterestRate);
    event LiquidationParamsSetup (address indexed user,
                                  uint256 _liquidationThreshold,
                                  uint256 _liquidationFee,
                                  uint256 _minLiquidationThreshold,
                                  uint256 _maxLiquidationThreshold,
                                  uint256 _minLiquidationAmount,
                                  uint256 _maxLiquidationAmount,
                                  uint256 _liquidationDiscountRate,
                                  string _liquidationBonusType);
    event OracleParamsSetup (address indexed user,
                             address _oracleAddress,
                             uint256 _heartbeat,
                             uint256 _decimals);
    event CollateralParamsSetup (address indexed user,
                                 address indexed _asset,
                                 uint256 _minCollateralAmount,
                                 uint256 _maxCollateralAmount,
                                 uint256 _collateralFactor,
                                 bool _isSupported);

    address public owner;

    struct DepositParams {
        uint256 minDepositAmount;
        uint256 maxDepositAmount;
        uint256 depositFee;
        uint256 minLockupPeriod;
        uint256 maxLockupPeriod;
    }

    struct InterestRateParams {
        uint256 baseRate;
        uint256 reserveFactor;
        uint256 maxInterestRate;
        uint256 minInterestRate;
    }

    struct BorrowParams {
        uint256 minBorrowAmount;
        uint256 maxBorrowAmount;
        uint256 borrowFee;
        uint256 minRepaymentPeriod;
        uint256 maxRepaymentPeriod; 
        InterestRateParams interestRate;  
    }

    struct LiquidationParams {
        uint256 liquidationThreshold;
        uint256 liquidationFee;
        uint256 minLiqudationThreshold;
        uint256 maxLiquidationThreshold;
        uint256 minLiquidationAmount;
        uint256 maxLiquidationAmount;
        uint256 liquidationDiscountRate;
        string liqudationBonusType;
    }

    struct OracleParams {
        address oracleAddress;  // e.g., Chainlink feed address
        uint256 heartbeat;      // max age for valid price
        uint256 decimals;       // oracle decimal places
    }

    struct CollateralParams {
        address asset;
        uint256 minCollateralAmount;
        uint256 maxCollateralAmount;
        uint256 l2b; // % of value that can be borrowed (e.g., 75%)
        bool isSupported;
    }

    bool public depositsPaused;
    bool public borrowingPaused;
    bool public liquidationPaused;

    DepositParams public depositParams;
    BorrowParams public borrowParams;
    LiquidationParams public liquidationParams;
    OracleParams public oracleParams;
    CollateralParams public collateralParams;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }
    constructor(address _owner) {
        owner = _owner;
        // depositsPaused = false;
        // borrowingPaused = false;
        // liquidationPaused = false;

        // depositParams = DepositParams({
        //     minDepositAmount: 0,
        //     maxDepositAmount: type(uint256).max,
        //     depositFee: 0,
        //     minLockupPeriod: 0,
        //     maxLockupPeriod: type(uint256).max
        // });

        // borrowParams = BorrowParams({
        //     minBorrowAmount: 0,
        //     maxBorrowAmount: type(uint256).max,
        //     borrowFee: 0,
        //     minRepaymentPeriod: 0,
        //     maxRepaymentPeriod: type(uint256).max,
        //     interestRate: InterestRateParams({
        //         baseRate: 0,
        //         reserveFactor: 0,
        //         maxInterestRate: type(uint256).max,
        //         minInterestRate: 0
        //     })
        // });

        // liquidationParams = LiquidationParams({
        //     liquidationThreshold: 0,
        //     liquidationFee: 0,
        //     minLiqudationThreshold: 0,
        //     maxLiquidationThreshold: type(uint256).max,
        //     minLiquidationAmount: 0,
        //     maxLiquidationAmount: type(uint256).max,
        //     liquidationBonusRate: 0,
        //     liqudationBonusType: ""
        // });

        // oracleParams = OracleParams({
        //     oracleAddress: address(0),
        //     heartbeat: 3600, // default to 1 hour
        //     decimals: 18 // default to 18 decimals
        // });

        // collateralParams = CollateralParams({
        //     asset: address(0),
        //     minCollateralAmount: 0,
        //     maxCollateralAmount: type(uint256).max,
        //     collateralFactor: 75, // default to 75%
        //     isSupported: false
        // });
    }

    function initialize (bool _depositPaused, bool _borrowingPaused, bool _liquidationPaused) external onlyOwner() {
        depositsPaused = _depositPaused;
        borrowingPaused = _borrowingPaused;
        liquidationPaused = _liquidationPaused;
    }

    function getMinDeposit() public view returns (uint256) {
        return depositParams.minDepositAmount;
    }

    function getMaxDeposit() public view returns (uint256) {
        return depositParams.maxDepositAmount;
    }

    function getMinLockupPeriod() public view returns (uint256) {
        return depositParams.minLockupPeriod;
    }
    function getMaxLockupPeriod() public view returns (uint256) {
        return depositParams.maxLockupPeriod;
    }


    function get_max_collateral_amount() public view returns (uint256) {
        return collateralParams.maxCollateralAmount;
    }
    function get_min_collateral_amount() public view returns (uint256) {
        return collateralParams.minCollateralAmount;
    }
    function getL2B() public view returns (uint256) {
        return collateralParams.l2b;
    }

    function get_base_interest_rate() public view returns (uint256) {
        return borrowParams.interestRate.baseRate;
    }
    function get_reserve_factor() public view returns (uint256) {
        return borrowParams.interestRate.reserveFactor;
    }
    function getMaxInterestRate() public view returns (uint256) {
        return borrowParams.interestRate.maxInterestRate;
    }
    function getMinInterestRate() public view returns (uint256) {
        return borrowParams.interestRate.minInterestRate;
    }
    function getMinBorrowAmount() public view returns (uint256) {
        return borrowParams.minBorrowAmount;
    }
    function getMaxBorrowAmount() public view returns (uint256) {
        return borrowParams.maxBorrowAmount;
    }
    function getBorrowFee() public view returns (uint256) {
        return borrowParams.borrowFee;
    }
    function getMinRepaymentPeriod() public view returns (uint256) {
        return borrowParams.minRepaymentPeriod;
    }
    function getMaxRepaymentPeriod() public view returns (uint256) {
        return borrowParams.maxRepaymentPeriod;
    }
    function getLiquidationDiscountRate() public view returns (uint256) {
        return liquidationParams.liquidationDiscountRate;
    }

       function getLiquidationThreshold() public view returns (uint256) {
        return liquidationParams.liquidationThreshold;
    }


    function set_deposit_params(
        uint256 _minDepositAmount,
        uint256 _maxDepositAmount,
        uint256 _depositFee,
        uint256 _minLockupPeriod,
        uint256 _maxLockupPeriod
    ) external onlyOwner {
        depositParams = DepositParams({
            minDepositAmount: _minDepositAmount,
            maxDepositAmount: _maxDepositAmount,
            depositFee: _depositFee,
            minLockupPeriod: _minLockupPeriod,
            maxLockupPeriod: _maxLockupPeriod
        });
        emit DepositParamsSetup(owner, _minDepositAmount, _maxDepositAmount, _depositFee, _minLockupPeriod, _maxLockupPeriod);
    }

    function set_borrow_params(
        uint256 _minBorrowAmount,
        uint256 _maxBorrowAmount,
        uint256 _borrowFee,
        uint256 _minRepaymentPeriod,
        uint256 _maxRepaymentPeriod,
        uint256 _baseRate,
        uint256 _reserveFactor,
        uint256 _maxInterestRate,
        uint256 _minInterestRate
    ) external onlyOwner{
        InterestRateParams memory _interestRate = InterestRateParams({
            baseRate: _baseRate, 
            reserveFactor: _reserveFactor, 
            maxInterestRate: _maxInterestRate, 
            minInterestRate: _minInterestRate 
        });

        borrowParams = BorrowParams({
            minBorrowAmount: _minBorrowAmount,
            maxBorrowAmount: _maxBorrowAmount,
            borrowFee: _borrowFee,
            minRepaymentPeriod: _minRepaymentPeriod,
            maxRepaymentPeriod: _maxRepaymentPeriod,
            interestRate: _interestRate
        });

        emit BorrowParamsSetup(owner, _minBorrowAmount, _maxBorrowAmount, _borrowFee, _minRepaymentPeriod, _maxRepaymentPeriod, _baseRate, _reserveFactor, _maxInterestRate, _minInterestRate);
    }

    function set_liquidation_params(
        uint256 _liquidationThreshold,
        uint256 _liquidationFee,
        uint256 _minLiquidationThreshold,
        uint256 _maxLiquidationThreshold,
        uint256 _minLiquidationAmount,
        uint256 _maxLiquidationAmount,
        uint256 _liquidationDiscountRate,
        string memory _liquidationBonusType
    ) external onlyOwner{
        liquidationParams = LiquidationParams({
            liquidationThreshold: _liquidationThreshold,
            liquidationFee: _liquidationFee,
            minLiqudationThreshold: _minLiquidationThreshold,
            maxLiquidationThreshold: _maxLiquidationThreshold,
            minLiquidationAmount: _minLiquidationAmount,
            maxLiquidationAmount: _maxLiquidationAmount,
            liquidationDiscountRate: _liquidationDiscountRate,
            liqudationBonusType: _liquidationBonusType
        });
        emit LiquidationParamsSetup(owner, _liquidationThreshold, _liquidationFee, _minLiquidationThreshold, _maxLiquidationThreshold, _minLiquidationAmount, _maxLiquidationAmount, _liquidationDiscountRate, _liquidationBonusType);
    }

    function set_oracle_params(
        address _oracleAddress,
        uint256 _heartbeat,
        uint256 _decimals
    ) external onlyOwner{
        oracleParams = OracleParams({
            oracleAddress: _oracleAddress,
            heartbeat: _heartbeat,
            decimals: _decimals
        });
        emit OracleParamsSetup(owner, _oracleAddress, _heartbeat, _decimals);
    }

    function set_collateral_params (
        address _asset,
        uint256 _minCollateralAmount,
        uint256 _maxCollateralAmount,
        uint256 _collateralFactor,
        bool _isSupported
    ) external onlyOwner{
        CollateralParams memory _collateral = CollateralParams({
            asset: _asset,
            minCollateralAmount: _minCollateralAmount,
            maxCollateralAmount: _maxCollateralAmount,
            l2b: _collateralFactor,
            isSupported: _isSupported
        });
        collateralParams = _collateral;
        emit CollateralParamsSetup(owner, _asset, _minCollateralAmount, _maxCollateralAmount, _collateralFactor, _isSupported);
    }
}