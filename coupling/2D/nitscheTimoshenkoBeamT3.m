% This file implements the Nitsche method to join two non-matching meshes.
% Non-matching triangular meshes.
%
% Timoshenko beam in bending.
%
% Vinh Phu Nguyen
% Cardiff University, UK
% 3 July 2013

addpath ../fem_util/
addpath ../gmshFiles/
addpath ../post-processing/
addpath ../fem-functions/
addpath ../analytical-solutions/

clear all
colordef black
state = 0;
tic;

opts = struct('Color','rgb','Bounds','tight','FontMode','fixed','FontSize',20);
%exportfig(gcf,'splinecurve.eps',opts)


% MATERIAL PROPERTIES
E0  = 30e6;  % Young?s modulus
nu0 = 0.3;  % Poisson?s ratio

% BEAM PROPERTIES
L  = 48;     % length of the beam
c  = 3;      % the distance of the outer fiber of the beam from the mid-line
t  = 2*c;

plotMesh  = 1;

% TIP LOAD
P = 1000; % the peak magnitude of the traction at the right edge
I0=2*c^3/3;  % the second polar moment of inertia of the beam cross-section.


% COMPUTE ELASTICITY MATRIX
C=E0/(1-nu0^2)*[   1      nu0          0;
    nu0        1          0;
    0        0  (1-nu0)/2 ];

% penalty parameter

alpha = 1e10;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% GENERATE FINITE ELEMENT MESH
%

disp([num2str(toc),'   GENERATING MESH'])

% MESH PROPERTIES

elemType = 'T3'; % the element type used in the FEM simulation;

% domain 1
numy1     = 8;
numx1     = 10;

L1 = 24;
% meshing for domain1
nnx=numx1+1;
nny=numy1+1;
node1=square_node_array([0 -c],[L1 -c],[L1 c],[0 c],nnx,nny);
node_pattern1=[ 1 2 nnx+1 ];
node_pattern2=[ 2 nnx+2 nnx+1 ];
inc_u=1;
inc_v=nnx;
element1=[make_elem(node_pattern1,numx1,numy1,inc_u,inc_v);
          make_elem(node_pattern2,numx1,numy1,inc_u,inc_v) ];

% domain 2
numy2     = 8;
numx2     = 10;

% meshing for domain2
nnx=numx2+1;
nny=numy2+1;
node2=square_node_array([L1 -c],[L -c],[L c],[L1 c],nnx,nny);
node_pattern1=[ 1 2 nnx+1 ];
node_pattern2=[ 2 nnx+2 nnx+1 ];
inc_u=1;
inc_v=nnx;
element2=[make_elem(node_pattern1,numx2,numy2,inc_u,inc_v);
          make_elem(node_pattern2,numx2,numy2,inc_u,inc_v) ];

C1 = 4*E0*numx1/L;
%alpha=C1;

% boundary mesh for domain 1
bndMesh1 = [];
for i=1:numy1
    bndMesh1 = [bndMesh1; numx1*i ];
end

% boundary mesh for domain 2
bndMesh2 = [];
for i=1:numy2
    bndMesh2 = [bndMesh2; numx2*(i-1)+1 ];
end

% PLOT MESH
if ( plotMesh )
    clf
    plot_mesh(node1,element1,elemType,'g.-',1.9);
    plot_mesh(node2,element2,elemType,'r.-',1.7);
    plot_mesh(node1,element1([1 2 3 4],:),elemType,'cy-',1.9);
    hold on
    axis off
    axis([0 L -c c])
end


% boundary edges

bndNodes  = find(node1(:,1)==L1);
bndEdge1  = zeros(numy1,2);

for i=1:numy1
    bndEdge1(i,:) = bndNodes(i:i+1);
end

map = ones(numy1,1);
d   = numy1/numy2;
for i=1:numy2
    map(d*(i-1)+1:d*(i-1)+d) = i;
end

[W1,Q1]=quadrature( 2, 'GAUSS', 1 ); % two point quadrature

GP1 = [];
GP2 = [];

for e=1:numy1
    sctrEdge=bndEdge1(e,:);
    sctr1    = element1(bndMesh1(e),:);
    sctr2    = element2(bndMesh2(map(e)),:);
    pts1     = node1(sctr1,:);
    pts2     = node2(sctr2,:);
    for q=1:size(W1)
        pt=Q1(q,:);
        wt=W1(q);
        [N,dNdxi]=lagrange_basis('L2',pt);  % element shape functions
        J0=dNdxi'*node1(sctrEdge,:);
        detJ0=norm(J0);
        J0 = J0/detJ0;
        
        x=N'*node1(sctrEdge,:);
        X1 = global2LocalMap(x,pts1,elemType);
        X2 = global2LocalMap(x,pts2,elemType);
        GP1 = [GP1;X1 wt*detJ0 -J0(2) J0(1)];
        GP2 = [GP2;X2 wt*detJ0];
    end
end

% DEFINE BOUNDARIES

edgeElemType='L2';

% GET NODES ON DISPLACEMENT BOUNDARY
%      Here we get the nodes on the essential boundaries

fixedNode=find(node1(:,1)==0);
rightNode=find(node2(:,1)==L);

midNode1  = find(node1(:,2)==0);
midNode2  = find(node2(:,2)==0);

coupleNode1 = find(node1(:,1)==L1);
coupleNode2 = find(node2(:,1)==L1);

rightEdge   = zeros(numy2,2);

for i=1:numy2
    rightEdge(i,:) = rightNode(i:i+1);
end

uFixed=zeros(1,length(fixedNode))';  % a vector of u_x for the nodes
vFixed=zeros(1,length(fixedNode))';

for i=1:length(fixedNode)
    inode = fixedNode(i);
    pts   = node1(inode,:);
    ux    = P*pts(2)/(6*E0*I0)*(2+nu0)*(pts(2)^2-c^2);
    uy    = -P/(2*E0*I0)*nu0*pts(2)^2*L;
    uFixed(i)=ux;
    vFixed(i)=uy;
end

numdofs = size(node1,1) + size(node2,1);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DEFINE SYSTEM DATA STRUCTURES

disp([num2str(toc),' INITIALIZING DATA STRUCTURES'])

f=zeros(2*numdofs,1);          % external load vector
K=zeros(2*numdofs,2*numdofs); % stiffness matrix


%xs=1:numnode;                  % x portion of u and v vectors
%ys=(numnode+1):2*numnode;      % y portion of u and v vectors

% ******************************************************************************
% ***                          P R O C E S S I N G                           ***
% ******************************************************************************
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%% COMPUTE STIFFNESS MATRIX %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
disp([num2str(toc),'   COMPUTING STIFFNESS MATRIX'])

[W,Q]=quadrature( 2, 'GAUSS', 2 ); % 2x2 Gaussian quadrature

% for domain 1

for e=1:size(element1,1)                          % start of element loop
    sctr = element1(e,:);           % element scatter vector
    sctrB=[ sctr sctr+numdofs ]; % vector that scatters a B matrix
    nn=length(sctr);
    for q=1:size(W,1)
        pt=Q(q,:);
        wt=W(q);
        [N,dNdxi]=lagrange_basis(elemType,pt); % element shape functions
        J0=node1(sctr,:)'*dNdxi;                % element Jacobian matrix
        invJ0=inv(J0);
        dNdx=dNdxi*invJ0;
        
        B(1,1:nn)       = dNdx(:,1)';
        B(2,nn+1:2*nn)  = dNdx(:,2)';
        B(3,1:nn)       = dNdx(:,2)';
        B(3,nn+1:2*nn)  = dNdx(:,1)';
        
        % COMPUTE ELEMENT STIFFNESS AT QUADRATURE POINT
        K(sctrB,sctrB)=K(sctrB,sctrB)+B'*C*B*W(q)*det(J0);
    end  % of quadrature loop
end

% for domain 2

%element2 = element2 + size(node1,1);

for e=1:size(element2,1)                          % start of element loop
    sctr  = element2(e,:);           % element scatter vector
    sctr2 = sctr + size(node1,1);
    sctrB = [ sctr2 sctr2+numdofs ]; % vector that scatters a B matrix
    nn=length(sctr);
    for q=1:size(W,1)
        pt=Q(q,:);
        wt=W(q);
        [N,dNdxi]=lagrange_basis(elemType,pt); % element shape functions
        J0=node2(sctr,:)'*dNdxi;                % element Jacobian matrix
        invJ0=inv(J0);
        dNdx=dNdxi*invJ0;
        
        B(1,1:nn)       = dNdx(:,1)';
        B(2,nn+1:2*nn)  = dNdx(:,2)';
        B(3,1:nn)       = dNdx(:,2)';
        B(3,nn+1:2*nn)  = dNdx(:,1)';
        
        % COMPUTE ELEMENT STIFFNESS AT QUADRATURE POINT
        K(sctrB,sctrB)=K(sctrB,sctrB)+B'*C*B*W(q)*det(J0);
    end  % of quadrature loop
end

% interface integrals

for i=1:numy1                     % start of element loop
    e1     = bndMesh1(i);
    e2     = bndMesh2(map(i));
    sctr1  = element1(e1,:);
    sctr2  = element2(e2,:);
    sctr2n = sctr2 + size(node1,1);
    
    sctrB1  = [ sctr1 sctr1+numdofs ];
    sctrB2  = [ sctr2n sctr2n+numdofs ];
    
    nn=length(sctr1);
    
    pts1 = node1(sctr1,:);
    pts2 = node2(sctr2,:);
    
    Kp11 = zeros(8,8);
    Kp12 = zeros(8,8);
    Kp22 = zeros(8,8);
    
    Kd11 = zeros(8,8);
    Kd12 = zeros(8,8);
    Kd21 = zeros(8,8);
    Kd22 = zeros(8,8);
    
    for q=2*i-1:2*i
        pt1=GP1(q,1:2);
        wt1=GP1(q,3);
        pt2=GP2(q,1:2);
        normal=GP1(q,4:5);
        n = [normal(1) 0 normal(2);0 normal(2) normal(1)];
        n=-n;
        [N1,dN1dxi]=lagrange_basis(elemType,pt1);
        [N2,dN2dxi]=lagrange_basis(elemType,pt2);
        
        J1 = pts1'*dN1dxi;
        J2 = pts2'*dN2dxi;
        
        dN1dx=dN1dxi*inv(J1);
        dN2dx=dN2dxi*inv(J2);
        
        B1(1,1:nn)       = dN1dx(:,1)';
        B1(2,nn+1:2*nn)  = dN1dx(:,2)';
        B1(3,1:nn)       = dN1dx(:,2)';
        B1(3,nn+1:2*nn)  = dN1dx(:,1)';
        
        B2(1,1:nn)       = dN2dx(:,1)';
        B2(2,nn+1:2*nn)  = dN2dx(:,2)';
        B2(3,1:nn)       = dN2dx(:,2)';
        B2(3,nn+1:2*nn)  = dN2dx(:,1)';
        
        Nm1(1,1:nn)       = N1';
        Nm1(2,nn+1:2*nn)  = N1';
        Nm2(1,1:nn)       = N2';
        Nm2(2,nn+1:2*nn)  = N2';
        
        % COMPUTE ELEMENT STIFFNESS AT QUADRATURE POINT
        
        Kp11 = Kp11 + alpha*(Nm1'*Nm1)*wt1;
        Kp12 = Kp12 + alpha*(Nm1'*Nm2)*wt1;
        Kp22 = Kp22 + alpha*(Nm2'*Nm2)*wt1;
        
        Kd11 = Kd11 + 0.5 * Nm1'* n * C * B1 *wt1;
        Kd12 = Kd12 + 0.5 * Nm1'* n * C * B2 *wt1;
        Kd21 = Kd21 + 0.5 * Nm2'* n * C * B1 *wt1;
        Kd22 = Kd22 + 0.5 * Nm2'* n * C * B2 *wt1;
        
    end  % of quadrature loop
    
    K(sctrB1,sctrB1)  = K(sctrB1,sctrB1)  - Kd11 - Kd11' + Kp11;
    K(sctrB1,sctrB2)  = K(sctrB1,sctrB2)  - Kd12 + Kd21' - Kp12;
    K(sctrB2,sctrB1)  = K(sctrB2,sctrB1)  + Kd21 - Kd12' - Kp12';
    K(sctrB2,sctrB2)  = K(sctrB2,sctrB2)  + Kd22 + Kd22' + Kp22;
end



%% External force

[W,Q]=quadrature( 3, 'GAUSS', 1 ); % three point quadrature

% RIGHT EDGE
for e=1:size(rightEdge,1) % loop over the elements in the right edge
    sctr=rightEdge(e,:);  % scatter vector for the element
    sctrx=sctr+ size(node1,1);           % x scatter vector
    sctry=sctrx+numdofs;  % y scatter vector
    for q=1:size(W,1)
        pt=Q(q,:);
        wt=W(q);
        [N,dNdxi]=lagrange_basis(edgeElemType,pt);  % element shape functions
        J0=dNdxi'*node2(sctr,:);
        detJ0=norm(J0);
        yPt=N'*node2(sctr,2);
        fyPt=-P*(c^2-yPt^2)/(2*I0);
        %fyPt=-P;
        f(sctry)=f(sctry)+N*fyPt*detJ0*wt;
    end % of quadrature loop
end  % of element loop


%%%%%%%%%%%%%%%%%%% END OF STIFFNESS MATRIX COMPUTATION %%%%%%%%%%%%%%%%%%%


% APPLY ESSENTIAL BOUNDARY CONDITIONS
disp([num2str(toc),'   APPLYING BOUNDARY CONDITIONS'])
bcwt=mean(diag(K)); % a measure of the average size of an element in K
% used to keep the conditioning of the K matrix
udofs=fixedNode;           % global indecies of the fixed x displacements
vdofs=fixedNode+numdofs;   % global indecies of the fixed y displacements
f=f-K(:,udofs)*uFixed;  % modify the force vector
f=f-K(:,vdofs)*vFixed;
K(udofs,:)=0;
K(vdofs,:)=0;
K(:,udofs)=0;
K(:,vdofs)=0;
K(udofs,udofs)=bcwt*speye(length(udofs)); % put ones*bcwt on the diagonal
K(vdofs,vdofs)=bcwt*speye(length(vdofs));
f(udofs)=bcwt*speye(length(udofs))*uFixed;
f(vdofs)=bcwt*speye(length(udofs))*vFixed;

% SOLVE SYSTEM
disp([num2str(toc),'   SOLVING SYSTEM'])
U=K\f;

%******************************************************************************
%*** POST - PROCESSING ***
%***************************************************

Ux1 = U(1:size(node1,1));
Uy1 = U([1:size(node1,1)]+numdofs);

Ux2 = U(1+size(node1,1):size(node1,1)+size(node2,1));
Uy2 = U([1+size(node1,1):size(node1,1)+size(node2,1)]+numdofs);

% Here we plot the stresses and displacements of the solution. As with the
% mesh generation section we don?t go into too much detail - use help
% ?function name? to get more details.
disp([num2str(toc),'   POST-PROCESSING'])

scaleFact=100.;
fn=1;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% PLOT DEFORMED DISPLACEMENT PLOT
%Ux = U(xs);
%Uy = U(ys);

figure
clf
hold on
plot_field(node1+scaleFact*[Ux1 Uy1],element1,elemType,Ux1);
plot_field(node2+scaleFact*[Ux2 Uy2],element2,elemType,Ux2);
plot_mesh(node1+scaleFact*[Ux1 Uy1],element1,elemType,'r.-',1);
plot_mesh(node2+scaleFact*[Ux2 Uy2],element2,elemType,'w.-',1);
%colorbar
axis off
%title('DEFORMED DISPLACEMENT IN Y-DIRECTION')

% Comapre numerical displacement to exact value


Uym1  = U(midNode1+numdofs);
Uym2  = U(midNode2+ size(node1,1)+numdofs);


xx = [node1(midNode1,1);node2(midNode2,1)];
u  = [Uym1;  Uym2];

y= 0;
x      = linspace(0,L,200);
D=t;
uExact = -1000/6/E0/I0*(3*nu0*y*y*(L-x)+(4+5*nu0)*D*D*x/4+(3*L-x).*x.^2);



colordef white
figure,set (gcf,'Color','w')
set(gca,'FontSize',14)
hold on
plot(x,uExact,'k-','LineWidth',1.4);
plot(xx,u,'o','MarkerEdgeColor','k',...
    'MarkerFaceColor','g',...
    'MarkerSize',6.5);
h=legend('exact','coupling');
xlabel('x')
ylabel('w')
grid on

%%

stress=zeros(size(element1,1),size(element1,2),3);

stressPoints=[-1 -1;1 -1;1 1;-1 1];


for e=1:size(element1,1)
    sctr=element1(e,:);
    sctrB=[sctr sctr+numdofs];
    nn=length(sctr);
    Ce=C;
    
    for q=1:nn
        pt=stressPoints(q,:);
        [N,dNdxi]=lagrange_basis(elemType,pt);
        J0=node1(sctr,:)'*dNdxi;
        invJ0=inv(J0);
        dNdx=dNdxi*invJ0;
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % COMPUTE B MATRIX
        B=zeros(3,2*nn);
        B(1,1:nn)       = dNdx(:,1)';
        B(2,nn+1:2*nn)  = dNdx(:,2)';
        B(3,1:nn)       = dNdx(:,2)';
        B(3,nn+1:2*nn)  = dNdx(:,1)';
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % COMPUTE ELEMENT STRAIN AND STRESS AT STRESS POINT
        strain=B*U(sctrB);
        stress(e,q,:)=Ce*strain;
    end
end   % of element loop

stressComp=1;
figure
clf
plot_field(node1+scaleFact*[Ux1 Uy1],element1,elemType,stress(:,:,stressComp));
%plot_mesh(node2+scaleFact*[Ux2 Uy2],element2,elemType,'r.-',1);
hold on
%plot_mesh(node+scaleFact*[U(xs) U(ys)],element,elemType,'g.-');
%plot_mesh(node,element,elemType,'w--');
colorbar
title('DEFORMED STRESS PLOT, BENDING COMPONENT')

%%

elems1 = numx1*8+1:numx1*9;
elems2 = numx2*4+1:numx2*5;

sigma    = zeros(length(elems1)+length(elems2),2);
sigmaRef = zeros(length(elems1)+length(elems2),2);
xcoord   = zeros(length(elems1)+length(elems2),2);

for e=1:length(elems1)
    ie = elems1(e);
    sctr=element1(ie,:);
    sctrB=[sctr sctr+numdofs];
    nn=length(sctr);
    
    pt=[0 0];
    [N,dNdxi]=lagrange_basis(elemType,pt);
    J0=node1(sctr,:)'*dNdxi;
    invJ0=inv(J0);
    dNdx=dNdxi*invJ0;
    yPt=N'*node1(sctr,:);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % COMPUTE B MATRIX
    B=zeros(3,2*nn);
    B(1,1:nn)       = dNdx(:,1)';
    B(2,nn+1:2*nn)  = dNdx(:,2)';
    B(3,1:nn)       = dNdx(:,2)';
    B(3,nn+1:2*nn)  = dNdx(:,1)';
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % COMPUTE ELEMENT STRAIN AND STRESS AT STRESS POINT
    strain=B*U(sctrB);
    stress=C*strain;
    sigma(e,1)    = stress(1);
    sigma(e,2)    = stress(3);
    sigmaRef(e,1) = 1000/I0*(L-yPt(1))*yPt(2);
    sigmaRef(e,2) = -1000/2/I0*(t^2/4-yPt(2)^2);
    xcoord(e,:)     = yPt;
end   % of element loop

for e=1:length(elems2)
    ie = elems2(e);
    sctr=element2(ie,:);
    sctr2 = sctr + size(node1,1);
    sctrB=[sctr2 sctr2+numdofs];
    nn=length(sctr);
    
    pt=[0 0];
    [N,dNdxi]=lagrange_basis(elemType,pt);
    J0=node2(sctr,:)'*dNdxi;
    invJ0=inv(J0);
    dNdx=dNdxi*invJ0;
    yPt=N'*node2(sctr,:);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % COMPUTE B MATRIX
    B=zeros(3,2*nn);
    B(1,1:nn)       = dNdx(:,1)';
    B(2,nn+1:2*nn)  = dNdx(:,2)';
    B(3,1:nn)       = dNdx(:,2)';
    B(3,nn+1:2*nn)  = dNdx(:,1)';
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % COMPUTE ELEMENT STRAIN AND STRESS AT STRESS POINT
    strain=B*U(sctrB);
    stress=C*strain;
    sigma(e+length(elems1),1)    = stress(1);
    sigma(e+length(elems1),2)    = stress(3);
    sigmaRef(e+length(elems1),1) = 1000/I0*(L-yPt(1))*yPt(2);
    sigmaRef(e+length(elems1),2) = -1000/2/I0*(t^2/4-yPt(2)^2);
    xcoord(e+length(elems1),:)     = yPt;
end   % of element loop


colordef white
figure,set (gcf,'Color','w')
set(gca,'FontSize',14)
hold on
plot(xcoord(:,1),sigmaRef(:,1),'k-','LineWidth',1.4);
plot(xcoord(:,1),sigma(:,1),'o','MarkerEdgeColor','k',...
    'MarkerFaceColor','g',...
    'MarkerSize',6.5);
plot(xcoord(:,1),sigmaRef(:,2),'k-','LineWidth',1.4);
plot(xcoord(:,1),sigma(:,2),'s','MarkerEdgeColor','k',...
    'MarkerFaceColor','g',...
    'MarkerSize',6.5);
h=legend('sigmaxx-exact','sigmaxx-coupling','sigmaxy-exact','sigmaxy-coupling');
xlabel('x')
ylabel('stresses at y=0.375')
grid on
axis([0 48 -400 1000])

%%

%%
aa=20;
elems1 = aa:numx1:aa+numx1*(numy1-1);

sigma   = zeros(length(elems1),2);
sigmaRef = zeros(length(elems1),2);
xcoord     = zeros(length(elems1),2);

for e=1:length(elems1)
    ie = elems1(e);
    sctr=element1(ie,:);
    sctrB=[sctr sctr+numdofs];
    nn=length(sctr);
    
    pt=[1 0];
    [N,dNdxi]=lagrange_basis(elemType,pt);
    J0=node1(sctr,:)'*dNdxi;
    invJ0=inv(J0);
    dNdx=dNdxi*invJ0;
    yPt=N'*node1(sctr,:);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % COMPUTE B MATRIX
    B=zeros(3,2*nn);
    B(1,1:nn)       = dNdx(:,1)';
    B(2,nn+1:2*nn)  = dNdx(:,2)';
    B(3,1:nn)       = dNdx(:,2)';
    B(3,nn+1:2*nn)  = dNdx(:,1)';
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % COMPUTE ELEMENT STRAIN AND STRESS AT STRESS POINT
    strain=B*U(sctrB);
    stress=C*strain;
    sigma(e,1)    = stress(1);
    sigma(e,2)    = stress(3);
    sigmaRef(e,1) = 1000/I0*(L-yPt(1))*yPt(2);
    sigmaRef(e,2) = -1000/2/I0*(t^2/4-yPt(2)^2);
    xcoord(e,:)     = yPt;
end   % of element loop

colordef white
figure,set (gcf,'Color','w')
set(gca,'FontSize',14)
hold on
plot(xcoord(:,2),sigmaRef(:,2),'k-','LineWidth',1.4);
plot(xcoord(:,2),sigma(:,2),'o','MarkerEdgeColor','k',...
    'MarkerFaceColor','g',...
    'MarkerSize',6.5);
% plot(xcoord(:,2),sigmaRef(:,2),'k-','LineWidth',1.4);
% plot(xcoord(:,2),sigma(:,2),'s','MarkerEdgeColor','k',...
%     'MarkerFaceColor','g',...
%     'MarkerSize',6.5);
h=legend('sigmaxy-exact','sigmaxy-coupling');
xlabel('y')
ylabel('stresses at x=23.4')
grid on
%axis([0 5 -0.55 0])
%
%
% %%
%% compute sigmaXY on the coupling boundary
%


%%

coupleDisp1 = [U(coupleNode1) U(coupleNode1+numdofs)];
coupleDisp2 = [U(coupleNode2+ size(node1,1)) U(coupleNode2+size(node1,1)+numdofs)];



