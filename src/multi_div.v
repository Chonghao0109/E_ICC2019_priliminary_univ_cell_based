
// File Name:
//  mulit_div.v
//
// Interface:
//  
//  Author:
//    CHONG-HAO XU
//
//  Descritpion:
//    select: multi : 0
//            div   : 1   
//    


module multi_div
#(
  parameter SIZE_A = 128,
  parameter SIZE_B = 64,
  parameter SIGNED = 0,
  parameter STEP_SIZE = 2 
)(
  input wire clk,reset_n,
  input wire en,
  input wire select,
  input wire [SIZE_A-1:0] a,
  input wire [SIZE_B-1:0] b,
  output reg [SIZE_A+SIZE_B-1:0] P,
  output reg div_zero,
  output reg Valid,
  output reg Busy
);

  localparam  READ_IN       = 0,
              CALCULATE     = 1,
              PREPARE_DATA  = 2,
              DATA_OUT      = 3;


  reg [1:0] state,next_state;
  reg [9:0] state_counter;
  
  reg neg_signed;

  reg [SIZE_A-1:0] data_b;
  reg [SIZE_A+SIZE_B:0] r;  //a + 1'b0 + SIZE_B'b0

  always@(*)begin
    Valid <= (state == DATA_OUT) ? 1'b1:1'b0;
    Busy  <= (state == CALCULATE || state == PREPARE_DATA) ? 1'b1:1'b0;
  end

  always@(posedge clk or negedge reset_n)begin
    if(!reset_n)begin
      state <= READ_IN;
    end
    else begin
      state <= next_state;
    end  
  end


  always@(*)begin
    case(state)
     
      READ_IN:begin
        if(en)begin
          if(select && b==0)begin
            next_state = DATA_OUT;
          end else begin
            next_state = CALCULATE;
          end 
        end
        else next_state = READ_IN;
      end


      CALCULATE:    next_state = (state_counter == (SIZE_A/STEP_SIZE)-1) ? PREPARE_DATA:CALCULATE;

      PREPARE_DATA: next_state = DATA_OUT;

      DATA_OUT :    next_state = READ_IN;
     
      default:      next_state = READ_IN;

    endcase
  end


  always@(posedge clk or negedge reset_n)begin
    if(!reset_n)begin
      state_counter <= 0;
    end
    else begin
      if(state == CALCULATE)begin
        state_counter <= state_counter + 1;
      end
      else begin
        state_counter <= 0;
      end
    end
  end

  






  reg [SIZE_A-1:0] na;
  reg [SIZE_B-1:0] nb;

  reg in_select;
  integer i;
  always@(posedge clk or negedge reset_n)begin
    if(~reset_n)begin
      r = 0;
      data_b = 0;
      in_select = 0;
			P = 0;
      neg_signed = 0;
    end else begin


      case(state)
        
        READ_IN   :begin
          if(en)begin
            
            if(SIGNED)begin
              neg_signed = a[SIZE_A-1] ^ b[SIZE_B-1];
              na = a[SIZE_A-1] ? -a:a;
              nb = b[SIZE_B-1] ? -b:b;
            end
            else begin
              na = a;
              nb = b;
            end

            r = {na,1'b0,{SIZE_B{1'b0}}};
            data_b = nb;
            in_select = select;

          end  
        end
        
        
        
        
        CALCULATE :begin

          for(i=0;i<STEP_SIZE;i=i+1)begin 
            if(in_select)begin // Div

              r = {r[SIZE_A+SIZE_B-1:0],r[SIZE_A+SIZE_B]};
              if( r[SIZE_B:0] >= data_b)begin
                r[SIZE_B+1] = 1;
                r[SIZE_B:0] = r[SIZE_B:0] - data_b;
              end
              else r[SIZE_B+1] = 0;
              //$display("R:%b",r);
              
            end
            else begin //Multi

              r = r[SIZE_A+SIZE_B] ? ((r<<1)+data_b) : (r<<1);
              

              //$display("r:%b",r);

            end 
          end
        end

        PREPARE_DATA:begin
          
          if(in_select)begin
            P = r[ (SIZE_A+SIZE_B) -: SIZE_A];
          end else begin
            P = r[SIZE_A+SIZE_B-1:0];
          end
          
          if(neg_signed)begin
            P = -P;
          end
        end

      endcase
    end
  end




endmodule
