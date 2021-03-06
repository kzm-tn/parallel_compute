!** 
!C*** module solver_ICCG_mc
!C***
!
      module solver_ICCG_mc
      contains
!C
!C*** solve_ICCG
!C
      subroutine solve_ICCG_mc                                          &
     &         ( N, NPL, NPU, indexL, itemL, indexU, itemU, D, B, X,    &
     &           AL, AU, NCOLORtot, PEsmpTOT, SMPindex, SMPindexG,      &
     &           EPS, ITR, IER)

      use omp_lib
      implicit REAL*8 (A-H,O-Z)

      integer :: N, NL, NU, NCOLORtot, PEsmpTOT

      real(kind=8), dimension(N)   :: D
      real(kind=8), dimension(N)   :: B
      real(kind=8), dimension(N)   :: X

      real(kind=8), dimension(NPL) :: AL
      real(kind=8), dimension(NPU) :: AU

      integer, dimension(0:N)   :: indexL, indexU
      integer, dimension(NPL):: itemL
      integer, dimension(NPU):: itemU

      integer, dimension(0:NCOLORtot*PEsmpTOT):: SMPindex
      integer, dimension(0:PEsmpTOT)       :: SMPindexG

      real(kind=8), dimension(:,:), allocatable :: W

      integer, parameter ::  R= 1
      integer, parameter ::  Z= 2
      integer, parameter ::  Q= 2
      integer, parameter ::  P= 3
      integer, parameter :: DD= 4

!C
!C +------+
!C | INIT |
!C +------+
!C===

      allocate (W(N,4))

!$acc enter data 
!$acc& copyin(B,D,indexL,itemL,indexU,itemU,AL,AU) 
!$acc& create(X,W)

!$omp parallel do private(i)
!$acc kernels async(0) present(X,W,B)
!$acc loop independent
      do i= 1, N
        X(i)  = 0.d0
        W(i,2)= 0.0D0
        W(i,3)= 0.0D0
        W(i,4)= 0.0D0
        W(i,R)= B(i)
      enddo
!$acc end kernels

!$omp parallel private(ic,ip1,ip2,i,VAL,k)
      do ic= 1, NCOLORtot
        ip1= SMPindex((ic-1)*PEsmpTOT) + 1
        ip2= SMPindex((ic-1)*PEsmpTOT + PEsmpTOT)
!$omp do
!$acc kernels async(0) present(D,indexL,AL,itemL,W)
!$acc loop independent
        do i= ip1, ip2
          VAL= D(i)
          do k= indexL(i-1)+1, indexL(i)
            VAL= VAL - (AL(k)**2) * W(itemL(k),DD)
          enddo
          W(i,DD)= 1.d0/VAL
        enddo
!$acc end kernels
      enddo
!$omp end parallel
!C===

!C
!C +-----------------------+
!C | {r0}= {b} - [A]{xini} |
!C +-----------------------+
!C===

      BNRM2= 0.0D0
!$omp parallel do private(i) reduction(+:BNRM2)
!$acc kernels async(0) present(B)
!$acc loop reduction(+:BNRM2) gang vector(256)
      do i = 1, N
        BNRM2 = BNRM2 + B(i)  **2
      enddo
!$acc end kernels
!$acc wait(0)
!C===

!C
!C***************************************************************  ITERATION
      ITR= N

      do L= 1, ITR
!C
!C +----------------+
!C | {z}= [Minv]{r} |
!C +----------------+
!C===      

!$omp parallel do private(i)
!$acc kernels async(0) present(W)
!$acc loop independent 
      do i = 1, N
        W(i,Z)= W(i,R)
      enddo
!$acc end kernels


!$omp parallel private(ic,ip1,ip2,i,WVAL,k)
      do ic= 1, NCOLORtot
        ip1= SMPindex((ic-1)*PEsmpTOT) + 1
        ip2= SMPindex((ic-1)*PEsmpTOT + PEsmpTOT)
!$omp do
!$acc kernels async(0) present(W,indexL,itemL,AL)
!$acc loop independent
        do i= ip1, ip2
          WVAL= W(i,Z)
          do k= indexL(i-1)+1, indexL(i)
            WVAL= WVAL -  AL(k) * W(itemL(k),Z)
          enddo
          W(i,Z)= WVAL * W(i,DD)
        enddo
!$acc end kernels
      enddo
!$omp end parallel


!$omp parallel private(ic,ip1,ip2,i,SW,k)
      do ic= NCOLORtot, 1, -1
        ip1= SMPindex((ic-1)*PEsmpTOT) + 1
        ip2= SMPindex((ic-1)*PEsmpTOT + PEsmpTOT)
!$omp do
!$acc kernels async(0) present(indexU,AU,W,itemU) 
!$acc loop independent
        do i= ip1, ip2
          SW  = 0.0d0
          do k= indexU(i-1)+1, indexU(i)
            SW= SW + AU(k) * W(itemU(k),Z)
          enddo
          W(i,Z)= W(i,Z) - W(i,DD) * SW
        enddo
!$acc end kernels
      enddo
!$omp end parallel
!C===

!C
!C +-------------+
!C | RHO= {r}{z} |
!C +-------------+
!C===
      RHO= 0.d0
!$omp parallel do private(i) reduction(+:RHO)
!$acc kernels async(0) present(W)
!$acc loop reduction(+:RHO) gang vector(256)
      do i = 1, N
        RHO= RHO + W(i,R)*W(i,Z)   
      enddo
!$acc end kernels
!$acc wait(0)
!C===

!C
!C +-----------------------------+
!C | {p} = {z} if      ITER=1    |
!C | BETA= RHO / RHO1  otherwise |
!C +-----------------------------+
!C===
      if ( L.eq.1 ) then
!$omp parallel do private(i)
!$acc kernels async(0) present(W)
!$acc loop independent
        do i = 1, N
          W(i,P)= W(i,Z)
        enddo
!$acc end kernels
       else
        BETA= RHO / RHO1
!$omp parallel do private(i)
!$acc kernels async(0) present(W)
!$acc loop independent
        do i = 1, N
          W(i,P)= W(i,Z) + BETA*W(i,P)
        enddo
!$acc end kernels
      endif
!C===

!C
!C +-------------+
!C | {q}= [A]{p} |
!C +-------------+
!C===        
!$omp parallel do private(i,VAL,k)
!$acc kernels async(0) present(D,W,indexL,itemL,AL,AU)
!$acc loop independent
      do i= 1, N
        VAL= D(i)*W(i,P)
        do k= indexL(i-1)+1, indexL(i)
          VAL= VAL + AL(k)*W(itemL(k),P)
        enddo 
        do k= indexU(i-1)+1, indexU(i)
          VAL= VAL + AU(k)*W(itemU(k),P)
        enddo 
        W(i,Q)= VAL
      enddo
!$acc end kernels
!C===

!C
!C +---------------------+
!C | ALPHA= RHO / {p}{q} |
!C +---------------------+
!C===
      C1= 0.d0
!$omp parallel do private(i) reduction(+:C1)
!$acc kernels async(0) present(W)
!$acc loop reduction(+:C1) gang vector(256)
      do i = 1, N
        C1= C1 + W(i,P)*W(i,Q)
      enddo
!$acc end kernels
!$acc wait(0)

      ALPHA= RHO / C1
!C===


!C
!C +----------------------+
!C | {x}= {x} + ALPHA*{p} |
!C | {r}= {r} - ALPHA*{q} |
!C +----------------------+
!C===
!$omp parallel do private(i)
!$acc kernels async(0) present(X,W)
!$acc loop independent
      do i = 1, N
        X(i)  = X(i)   + ALPHA * W(i,P)
        W(i,R)= W(i,R) - ALPHA * W(i,Q)
      enddo
!$acc end kernels

      DNRM2= 0.d0
!$omp parallel do private(i) reduction(+:DNRM2)
!$acc kernels async(0) present(W)
!$acc loop reduction(+:DNRM2) gang vector(256)
      do i = 1, N
        DNRM2= DNRM2 + W(i,R)**2
      enddo
!$acc end kernels
!$acc wait(0)
!C===

      ERR = dsqrt(DNRM2/BNRM2)
      if (mod(L,100).eq.1) then
        write (*,'(i5,2(1pe16.6))') L, ERR
      endif

        if (ERR .lt. EPS) then
          IER = 0
          goto 900
         else
          RHO1 = RHO
        endif

      enddo
      IER = 1

  900 continue

!$acc exit data 
!$acc& delete(B,D,indexL,itemL,indexU,itemU,AL,AU,W) 
!$acc& copyout(X) 

      write (*,'(i5,2(1pe16.6))') L, ERR
      ITR= L
!      EPS= ERR

      deallocate (W)

      return

      end subroutine  solve_ICCG_mc
      end module     solver_ICCG_mc



