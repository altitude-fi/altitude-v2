// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

library Constants {
    // Assets
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant crvUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant sUSD = 0xC25a3A3b969415c80451098fa907EC722572917F;
    address public constant mUSD = 0x1AEf73d49Dedc4b1778d0706583995958Dc862e6;
    address public constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant aUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    // Account addresses
    address public constant account_ALPHA = 0xACd03dadf67eCEEF4b5f871ACe553E4f79ea48a4;
    address public constant account_BETA = 0xc49C8f4106fDb64977d4019b1894f8CC4875480a;
    address public constant account_GAMMA = 0xc13166BbEB50591AD3b546C9B1C3e3F6dB1a94b8;
    address public constant account_TREASURY = 0xe0081BbC8B328AcEf69aac8DF5fDFBDde87376ac;

    // Aave V2
    address public constant aave_v2_Pool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address public constant aave_v2_Token = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address public constant aave_v2_Provider = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;

    // Aave V3
    address public constant aave_v3_Pool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant aave_v3_Oracle = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;
    address public constant aave_v3_Provider = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address public constant aave_v3_DataProvider = 0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3;
    address public constant aave_v3_IncentivesController = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;

    // Morpho
    address public constant morpho_Pool = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant morpho_Vault_DAI = 0x500331c9fF24D9d11aee6B07734Aa72343EA74a5;
    address public constant morpho_Vault_MEV_Capital_USDC = 0xd63070114470f685b75B74D60EEc7c1113d33a3D;
    address public constant morpho_Vault_Gauntlet_USDC_Core = 0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458;
    bytes32 public constant morpho_Market_WSTETH_USDC =
        0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc;
    bytes32 public constant morpho_Market_cbBTC_USDC =
        0x64d65c9a2d91c36d56fbc42d69e979335320169b3df63bf92789e2c8883fcc64;

    // Uniswap V3
    uint24 public constant uniswap_v3_FeeTier_100 = 100; // 0.01%
    uint24 public constant uniswap_v3_FeeTier_500 = 500; // 0.05%
    uint24 public constant uniswap_v3_FeeTier_3000 = 3000; // 0.3%
    uint24 public constant uniswap_v3_FeeTier_10000 = 10000; // 1%
    address public constant uniswap_v3_Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant uniswap_v3_SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant uniswap_v3_ViewQuoter = 0x5e55C9e631FAE526cd4B0526C4818D6e0a9eF0e3;

    // Chainlink
    address public constant chainlink_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant chainlink_BTC = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
    address public constant chainlink_USD = 0x0000000000000000000000000000000000000348;
    address public constant chainlink_FeedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;

    // Curve
    address public constant curve_Router = 0xF0d4c12A5768D806021F80a262B4d39d26C58b8D;
    address public constant curve_MIMZap = 0xA79828DF1850E8a3A3064576f380D90aECDD3359;
    address public constant curve_MUSDZap = 0x803A2B40c5a9BB2B86DD630B274Fa2A9202874C2;
    address public constant curve_sUSDZap = 0xFCBa3E75865d2d561BE8D220616520c171F12851;
    address public constant curve_RewardToken_crvUSD = 0xbe99C9A460488Ef88eF46db02a1222563acAd636;
    address public constant curve_Pool_3 = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address public constant curve_Pool_MIM = 0x5a6A4D54456819380173272A5E8E9B9904BdF41B;
    address public constant curve_Pool_gUSD = 0x4f062658EaAF2C1ccf8C8e36D6824CDf41167956;
    address public constant curve_Pool_mUSD = 0x8474DdbE98F5aA3179B3B3F5942D724aFcdec9f6;
    address public constant curve_Pool_sUSD = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;
    address public constant curve_Pool_cvxETH = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;
    address public constant curve_Pool_TriCRV = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;
    address public constant curve_Pool_USDV_3crv = 0x00e6Fd108C4640d21B40d02f18Dd6fE7c7F725CA;
    address public constant curve_Pool_Tricrypto2 = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    address public constant curve_Pool_crvUSD_GHO = 0x86152dF0a0E321Afb3B0B9C4deb813184F365ADa;
    address public constant curve_Pool_USDT_crvUSD = 0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
    address public constant curve_Pool_USDC_crvUSD = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address public constant curve_Pool_LUSD_crvUSD = 0x9978c6B08d28d3B74437c917c5dD7C026df9d55C;
    address public constant curve_Pool_crvUSD_SUSD = 0x94cC50e4521bD271C1a997a3A4Dc815C2F920b41;
    address public constant curve_Pool_crvUSD_USDP = 0xCa978A0528116DDA3cbA9ACD3e68bc6191CA53D0;
    address public constant curve_Pool_crvUSD_TUSD = 0x34D655069F4cAc1547E4C8cA284FfFF5ad4A8db0;
    address public constant curve_Pool_pyUSD_crvUSD = 0x625E92624Bc2D88619ACCc1788365A69767f6200;
    address public constant curve_Pool_Tricrypto_USDC = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;

    // [0 = MIM, 1 = 3CRV]
    function curve_MIMTokens() public pure returns (address[2] memory) {
        return [0x5a6A4D54456819380173272A5E8E9B9904BdF41B, 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490];
    }

    // [0 = MUSD, 1 = 3CRV]
    function curve_mUSDTokens() public pure returns (address[2] memory) {
        return [0x1AEf73d49Dedc4b1778d0706583995958Dc862e6, 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490];
    }

    // Convex
    address public constant convex_Booster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address public constant convex_RewardsToken_sUSDC_CRV = 0x22eE18aca7F3Ee920D01F25dA85840D12d98E8Ca;
    address public constant convex_RewardsToken_MIM_CRV = 0xFd5AbF66b003881b88567EB9Ed9c651F14Dc4771;
    address public constant convex_RewardsToken_mUSD_CRV = 0xDBFa6187C79f4fE4Cda20609E75760C5AaE88e52;

    // Pendle
    address public constant pendle_Token = 0x808507121B80c02388fAd14726482e061B8da827;
    address public constant pendle_Oracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
    address public constant pendle_Router = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address public constant pendle_RouterStatic = 0x263833d47eA3fA4a30f269323aba6a107f9eB14C;
    address public constant pendle_Market_SUSDE_Mar_25 = 0xcDd26Eb5EB2Ce0f203a84553853667aE69Ca29Ce;
    address public constant pendle_Market_aUSDC_Jun_25 = 0x8539B41CA14148d1F7400d399723827a80579414;
}
