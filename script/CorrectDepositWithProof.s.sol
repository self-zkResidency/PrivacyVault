// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyVault} from "../src/PrivacyVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CorrectDepositWithProof is Script {
    // Direcciones del contrato desplegado
    address constant PRIVACY_VAULT = 0x63127A6f30f0762e3e9BB467aF1eDFFbe0c24cB3;
    address constant CUSD_TOKEN = 0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b;
    
    // Monto a depositar (10 cUSD con 18 decimales)
    uint256 constant DEPOSIT_AMOUNT = 10e18;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(deployerPrivateKey);
        
        console.log("=== Deposito Correcto con Proof del Playground ===");
        console.log("Usuario:", user);
        console.log("Contrato PrivacyVault:", PRIVACY_VAULT);
        console.log("Monto a depositar:", DEPOSIT_AMOUNT / 1e18, "cUSD");
        
        // Crear instancias
        PrivacyVault vault = PrivacyVault(PRIVACY_VAULT);
        IERC20 cusd = IERC20(CUSD_TOKEN);
        
        // Verificar balance inicial
        uint256 initialBalance = cusd.balanceOf(user);
        console.log("Balance inicial de cUSD:", initialBalance / 1e18, "cUSD");
        
        if (initialBalance < DEPOSIT_AMOUNT) {
            console.log("ERROR: Balance insuficiente para el deposito");
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Aprobar el gasto
        console.log("Aprobando gasto de cUSD...");
        cusd.approve(PRIVACY_VAULT, DEPOSIT_AMOUNT);
        
        // Construir proofPayload con el formato correcto del playground
        bytes memory proofPayload = _buildCorrectProofPayload();
        
        // userContextData del playground (exacto)
        bytes memory userContextData = hex"000000000000000000000000000000000000000000000000000000000000a4ec000000000000000000000000c2564e41b7f5cb66d2d99466450cfebce9e8228f48656c6c6f2053464f";
        
        console.log("Datos del proof:");
        console.log("  proofPayload length:", proofPayload.length);
        console.log("  userContextData length:", userContextData.length);
        
        // Paso 1: Verificar usuario
        console.log("Paso 1: Verificando usuario con proof...");
        
        try vault.verifyUser(proofPayload, userContextData) {
            console.log("SUCCESS: Verificacion exitosa!");
            
            // Verificar que la verificacion fue exitosa
            bool verificationSuccess = vault.verificationSuccessful();
            console.log("Verificacion exitosa:", verificationSuccess);
            
            if (verificationSuccess) {
                console.log("Paso 2: Ejecutando deposito...");
                
                // Paso 2: Ejecutar deposito
                vault.executeDeposit();
                console.log("SUCCESS: Deposito ejecutado exitosamente!");
                
                // Verificar balances finales
                uint256 finalUserBalance = cusd.balanceOf(user);
                uint256 finalVaultBalance = cusd.balanceOf(PRIVACY_VAULT);
                
                console.log("Balance final del usuario:", finalUserBalance / 1e18, "cUSD");
                console.log("Balance final del vault:", finalVaultBalance / 1e18, "cUSD");
                console.log("Diferencia depositada:", (initialBalance - finalUserBalance) / 1e18, "cUSD");
            } else {
                console.log("ERROR: La verificacion no fue exitosa");
            }
            
        } catch Error(string memory reason) {
            console.log("ERROR: Error en verificacion:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("ERROR: Error de bajo nivel en deposito");
            console.log("Datos del error:");
            console.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
        
        console.log("=== Fin del test ===");
    }
    
    // Construir proofPayload con el formato correcto del playground
    function _buildCorrectProofPayload() internal pure returns (bytes memory) {
        // Attestation ID (1 = E_PASSPORT)
        bytes memory proofPayload = abi.encodePacked(bytes32(uint256(1)));
        
        // Public signals del playground (21 valores)
        uint256[] memory publicSignals = new uint256[](21);
        publicSignals[0] = 0;
        publicSignals[1] = 0;
        publicSignals[2] = 5917645764266387229099807922771871753544163856784761583567435202560;
        publicSignals[3] = 0;
        publicSignals[4] = 0;
        publicSignals[5] = 0;
        publicSignals[6] = 0;
        publicSignals[7] = 15253325420592599242012869407001693221004003441687668538291542579863885481852;
        publicSignals[8] = 1;
        publicSignals[9] = 14253012411674490410996254005369275634674577834368043363547479283703548661569;
        publicSignals[10] = 2;
        publicSignals[11] = 5;
        publicSignals[12] = 1;
        publicSignals[13] = 0;
        publicSignals[14] = 1;
        publicSignals[15] = 6;
        publicSignals[16] = 17359956125106148146828355805271472653597249114301196742546733402427978706344;
        publicSignals[17] = 7420120618403967585712321281997181302561301414016003514649937965499789236588;
        publicSignals[18] = 16836358042995742879630198413873414945978677264752036026400967422611478610995;
        publicSignals[19] = 3749473092307219433531089091852668441439628120673956915188416134815216896930;
        publicSignals[20] = 587649601260819379317151942660800124402838043785;
        
        // Agregar public signals
        for (uint256 i = 0; i < publicSignals.length; i++) {
            proofPayload = abi.encodePacked(proofPayload, bytes32(publicSignals[i]));
        }
        
        // Agregar proof (a, b, c) del playground
        // a
        proofPayload = abi.encodePacked(
            proofPayload,
            _toBytes32(3345114906489639166462431893186135969507300310055325033934335586933823530768),
            _toBytes32(18872822685136561318017049494416294030744321752779125311533762276104604365489)
        );
        
        // b[0]
        proofPayload = abi.encodePacked(
            proofPayload,
            _toBytes32(19563923816691378480953050031828636888365948255785674541666666482072388336588),
            _toBytes32(9822905883806772122253423052879816765684095136805246404694384554577337179879)
        );
        
        // b[1]
        proofPayload = abi.encodePacked(
            proofPayload,
            _toBytes32(7471493170431629079847933198112622302757269235972844475164298431966555356230),
            _toBytes32(1855252738479905204786491536738604229873815900188422660490720580069372012254)
        );
        
        // c
        proofPayload = abi.encodePacked(
            proofPayload,
            _toBytes32(9885592087468531325056467164553293702305869188987030207353348500074982910987),
            _toBytes32(19706311129785148822912682068275771500969933369833815577546421123562118368803)
        );
        
        return proofPayload;
    }
    
    // Helper function para convertir uint256 a bytes32
    function _toBytes32(uint256 value) internal pure returns (bytes32) {
        return bytes32(value);
    }
}
