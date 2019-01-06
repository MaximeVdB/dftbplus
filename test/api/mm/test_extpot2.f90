!--------------------------------------------------------------------------------------------------!
!  DFTB+: general package for performing fast atomistic simulations                                !
!  Copyright (C) 2018  DFTB+ developers group                                                      !
!                                                                                                  !
!  See the LICENSE file for terms of usage and distribution.                                       !
!--------------------------------------------------------------------------------------------------!

!> amber type calls to the DFTB+ API, building the full input tree for a water molecule example
program test_amber
  use, intrinsic :: iso_fortran_env, only : output_unit
  use dftbplus
  use dftbp_constants, only : AA__Bohr
  use extchargepot
  implicit none

  integer, parameter :: dp = kind(1.0d0)

  integer, parameter :: nAtom = 3

  integer, parameter :: nExtChrg = 2

  ! H2O coordinates (atomic units)
  real(dp), parameter :: initialCoords(3, nAtom) = reshape([&
      & 0.000000000000000E+00_dp, -0.188972598857892E+01_dp,  0.000000000000000E+00_dp,&
      & 0.000000000000000E+00_dp,  0.000000000000000E+00_dp,  0.147977639152057E+01_dp,&
      & 0.000000000000000E+00_dp,  0.000000000000000E+00_dp, -0.147977639152057E+01_dp], [3, nAtom])

  ! H2O atom types
  integer, parameter :: species(nAtom) = [1, 2, 2]

  ! External charges (positions and charges, again atomic units)
  real(dp), parameter :: extCharges(4, nExtChrg) = reshape([&
      &-0.94486343888717805E+00_dp,-0.94486343888717794E+01_dp, 0.17007541899969201E+01_dp, 2.5_dp,&
      & 0.43463718188810203E+01_dp,-0.58581533211004997E+01_dp, 0.26456176288841000E+01_dp, -1.9_dp&
      &], [4, nExtChrg])

  ! where to find the SK data.
  ! You should provide the skfiles as found in the external/slakos/origin/mio-1-1/ folder. These can
  ! be downloaded with the utils/get_opt_externals script
  character(100), parameter :: slakoFiles(2, 2) = reshape([character(100) :: &
      & "external/slakos/origin/mio-1-1/O-O.skf",&
      & "external/slakos/origin/mio-1-1/H-O.skf",&
      & "external/slakos/origin/mio-1-1/O-H.skf",&
      & "external/slakos/origin/mio-1-1/H-H.skf"], [2, 2])

  ! labels for l shells
  character(1), parameter :: maxAngNames(4) = ["s", "p", "d", "f"]

  type(TDftbPlus) :: dftbp
  type(TDftbPlusInput) :: input

  real(dp) :: merminEnergy
  real(dp) :: coords(3, nAtom), gradients(3, nAtom), extPot(nAtom), extPotGrad(3, nAtom)
  real(dp) :: atomCharges(nAtom), extChargeGrads(3, nExtChrg)
  type(fnode), pointer :: pRoot, pGeo, pHam, pDftb, pMaxAng, pSlakos, pType2Files, pAnalysis
  type(fnode), pointer :: pParserOpts

  !integer :: devNull

  ! Note: setting the global standard output to /dev/null will also suppress run-time error messages
  !open(newunit=devNull, file="/dev/null", action="write")
  !call TDftbPlus_init(dftbp, outputUnit=devNull)
  call TDftbPlus_init(dftbp)

  ! start a new instance
  call dftbp%getEmptyInput(input)
  ! get the root node of the input tree
  call input%getRootNode(pRoot)

  ! from the root fill the geometry block
  call setChild(pRoot, "Geometry", pGeo)
  call setChildValue(pGeo, "Periodic", .false.)
  call setChildValue(pGeo, "TypeNames", ["O", "H"])
  coords(:,:) = 0.0_dp
  call setChildValue(pGeo, "TypesAndCoordinates", reshape(species, [1, size(species)]), coords)

  ! from the root, fill the hamitonian block
  call setChild(pRoot, "Hamiltonian", pHam)
  call setChild(pHam, "Dftb", pDftb)
  call setChildValue(pDftb, "Scc", .true.)
  call setChildValue(pDftb, "SccTolerance", 1e-12_dp)
  call setChild(pDftb, "MaxAngularMomentum", pMaxAng)
  ! read angular momenta from SK data
  call setChildValue(pMaxAng, "O", maxAngNames(getMaxAngFromSlakoFile(slakoFiles(1, 1)) + 1))
  call setChildValue(pMaxAng, "H", maxAngNames(getMaxAngFromSlakoFile(slakoFiles(2, 2)) + 1))
  ! read the actual SK files in
  call setChild(pDftb, "SlaterKosterFiles", pSlakos)
  call setChild(pSlakos, "Type2FileNames", pType2Files)
  call setChildValue(pType2Files, "Prefix", "external/slakos/origin/mio-1-1/")
  call setChildValue(pType2Files, "Separator", "-")
  call setChildValue(pType2Files, "Suffix", ".skf")

  ! Analysis block for input
  call setChild(pRoot, "Analysis", pAnalysis)
  call setChildValue(pAnalysis, "CalculateForces", .true.)

  ! DFTB+ parser options
  call setChild(pRoot, "ParserOptions", pParserOpts)
  call setChildValue(pParserOpts, "ParserVersion", 5)
  
  print "(A)", 'Input tree in HSD format:'
  call dumpHsd(input%hsdTree, output_unit)
  
  call dftbp%setupCalculator(input)

  ! over-write coordinates
  coords(:,:) = initialCoords
  call dftbp%setGeometry(coords)

  ! add external potential from some charges
  call getPointChargePotential(extCharges(1:3,:), extCharges(4,:), coords, extPot, extPotGrad)
  call dftbp%setExternalPotential(atomPot=extPot, potGrad=extPotGrad)

  ! get energy, forces and charges
  call dftbp%getEnergy(merminEnergy)
  call dftbp%getGradients(gradients)
  call dftbp%getGrossCharges(atomCharges)

  ! get forces on the external charges
  call getPointChargeGradients(coords, atomCharges, extCharges(1:3,:), extCharges(4,:),&
      & extChargeGrads)

  print "(A,F15.10)", 'Expected Mermin Energy:', -0.398548033919583E+001_dp
  print "(A,F15.10)", 'Obtained Mermin Energy:', merminEnergy
  print "(A,3F15.10)", 'Expected gross charges:', -(6.49439832790185_dp - 6.0_dp),&
      & -(0.735827787218271E+000_dp - 1.0_dp), -(0.769773884872109E+000_dp - 1.0_dp)
  print "(A,3F15.10)", 'Obtained gross charges:', atomCharges

  print "(A,3F15.10)", 'Expected gradient of atom 1:', 0.176513637737736E-001_dp,&
      & -0.183137601772536E+000_dp, 0.319825151816764E-002_dp
  print "(A,3F15.10)", 'Obtained gradient of atom 1:', gradients(:,1)
  print "(A,3F15.10)", 'Expected gradient of atom 2:', -0.614022657776373E-002_dp,&
      & 0.955090293319614E-001_dp, 0.394035230277817E-001_dp
  print "(A,3F15.10)", 'Obtained gradient of atom 2:', gradients(:,2)
  print "(A,3F15.10)", 'Expected gradient of atom 3:', -0.377202598396707E-002_dp,&
      & 0.923535862104179E-001_dp, -0.402979579635372E-001_dp
  print "(A,3F15.10)", 'Obtained gradient of atom 3:', gradients(:,3)

  print "(A,3F15.10)", 'Expected gradient of charge 1:', -0.118623591287408E-002_dp,&
      & -0.695045328370150E-002_dp, 0.242761119930661E-002_dp
  print "(A,3F15.10)", 'Obtained gradient of charge 1:', extChargeGrads(:,1)
  print "(A,3F15.10)", 'Expected gradient of charge 2:', -0.655287529916873E-002_dp,&
      & 0.222543951385786E-002_dp, -0.473142778171874E-002_dp
  print "(A,3F15.10)", 'Obtained gradient of charge 2:', extChargeGrads(:,2)

  call TDftbPlus_destruct(dftbp)


end program test_amber
