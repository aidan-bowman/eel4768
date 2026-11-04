module multiplier (
                   input wire         i_clk,
                   input wire         i_rst,
                   input wire         i_start,
                   input wire [31:0]  i_mula,
                   input wire [31:0]  i_mulb,
                   input wire         i_mula_signed,
                   input wire         i_mulb_signed,
                   output wire [63:0] o_prod,
                   output wire        o_busy,
                   output wire        o_ready
                   );

    reg [63:0] multiplicand;
    reg [31:0] multiplier;
    reg [63:0] product;

    reg [2:0]  count;
    reg        busy;
    reg        ready;

    // Determine whether each operand is negative.
    wire       a_negative = i_mula_signed && i_mula[31];
    wire       b_negative = i_mulb_signed && i_mulb[31];

    // Convert negative operands to their unsigned magnitudes.
    wire [31:0] a_magnitude =
                a_negative ? (~i_mula + 32'd1) : i_mula;

    wire [31:0] b_magnitude =
                b_negative ? (~i_mulb + 32'd1) : i_mulb;

    // Remember whether the final product needs to be negative.
    reg         negate_product;

    // Process four multiplier bits per cycle.
    wire [63:0] sum0 =
                multiplier[0] ? product + multiplicand : product;

    wire [63:0] sum1 =
                multiplier[1] ? sum0 + (multiplicand << 1) : sum0;

    wire [63:0] sum2 =
                multiplier[2] ? sum1 + (multiplicand << 2) : sum1;

    wire [63:0] sum3 =
                multiplier[3] ? sum2 + (multiplicand << 3) : sum2;

    // Correct the sign of the final product, if necessary.
    wire [63:0] final_product =
                negate_product ? (~sum3 + 64'd1) : sum3;

    assign o_prod  = product;
    assign o_busy  = busy;
    assign o_ready = ready;

    always @(posedge i_clk) begin
        if (i_rst) begin
            multiplicand  <= 64'b0;
            multiplier    <= 32'b0;
            product       <= 64'b0;
            count         <= 3'b0;
            busy          <= 1'b0;
            ready         <= 1'b0;
            negate_product <= 1'b0;
        end
        else begin
            if (busy) begin
                // Save this cycle's partial product.
                if (count == 3'd7) begin
                    product <= final_product;
                    busy    <= 1'b0;
                    ready   <= 1'b1;
                end
                else begin
                    product <= sum3;
                    count   <= count + 1'b1;
                end

                // Move to the next group of four multiplier bits.
                multiplicand <= multiplicand << 4;
                multiplier   <= multiplier >> 4;
            end // if (busy)
            else if (i_start) begin
                // Start a new multiplication using operand magnitudes.
                multiplicand <= {32'b0, a_magnitude};
                multiplier   <= b_magnitude;
                product      <= 64'b0;

                // The product is negative if exactly one operand is negative.
                negate_product <= a_negative ^ b_negative;

                count <= 3'b0;
                busy  <= 1'b1;
                ready <= 1'b0;
            end // if (i_start)
            else if (ready) begin
                // Completion pulse lasts one cycle.
                ready <= 1'b0;
            end
        end // else: !if(i_rst)
    end // always @ (posedge i_clk)
    
endmodule // multiplier

